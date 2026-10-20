// physics.js — Rigidbody/Colliders da Unity com cannon-es.
// Na Unity todo primitivo ja nasce com colisor; aqui os primitivos do cenario viram corpos
// estaticos/cinematicos (seguem o objeto), e AddRigidbody cria corpos dinamicos.
// A simulacao roda no espaco local do "mundo" do jogo (o objeto raiz que o rig move),
// como a Unity faz ao mover o pai dos rigidbodies junto com a locomocao.
/* global THREE, EMRWEB */
'use strict';

(function () {
  const W = (window.EMRWEB = window.EMRWEB || {});
  const PB = {};
  W.physicsBridge = PB;

  const tmpM = new THREE.Matrix4(), invTop = new THREE.Matrix4();
  const vp = new THREE.Vector3(), vs = new THREE.Vector3();
  const vq = new THREE.Quaternion();

  function topOf(n) {
    let q = n;
    while (q && q.parent && q.parent !== W.rootNode) q = q.parent;
    return q;
  }

  function isActiveChain(n) {
    let q = n;
    while (q) { if (q.active === false) return false; q = q.parent; }
    return true;
  }

  class Physics {
    constructor(top) {
      const C = W.CANNON;
      this.C = C;
      this.top = top;
      this.world = new C.World({ gravity: new C.Vec3(0, -9.81, 0) });
      this.world.broadphase = new C.SAPBroadphase(this.world);
      this.world.allowSleep = true;
      this.world.defaultContactMaterial.friction = 0.45;
      this.world.defaultContactMaterial.restitution = 0.12;
      this.dyn = new Set();
      this.cols = new Set();
      this.pending = new Set();
      for (const n of W.nodes.values()) this.pending.add(n);
    }

    // pose do no relativa ao topo (three, espaco local do mundo do jogo)
    rel(n, fresh) {
      if (fresh !== false) {
        this.top.obj.updateWorldMatrix(true, false);
        n.obj.updateWorldMatrix(true, false);
        invTop.copy(this.top.obj.matrixWorld).invert();
      }
      tmpM.multiplyMatrices(invTop, n.obj.matrixWorld);
      tmpM.decompose(vp, vq, vs);
      return { p: vp.clone(), q: vq.clone(), s: new THREE.Vector3(Math.abs(vs.x), Math.abs(vs.y), Math.abs(vs.z)) };
    }

    shapeFor(n, s) {
      const C = this.C;
      const k = n.collider === 2 ? 'sphere' : (n.collider === 1 ? 'box' : n.kind);
      if (k === 'sphere') {
        const r = (n.collider === 2 ? n.colliderR : 0.5) * Math.max(s.x, s.y, s.z);
        return new C.Sphere(Math.max(0.01, r));
      }
      let hx = s.x / 2, hy = s.y / 2, hz = s.z / 2;
      if (n.kind === 'cylinder' || n.kind === 'capsule') { hy = s.y; }
      if (n.kind === 'plane') { hx = s.x * 5; hz = s.z * 5; hy = 0.01; }
      return new C.Box(new C.Vec3(Math.max(0.005, hx), Math.max(0.005, hy), Math.max(0.005, hz)));
    }

    eligible(n) {
      if (!n.obj.isMesh || n.kind === 'quad' || n.unlit || n.headAttach) return false;
      if (n.body) return false;
      if (topOf(n) !== this.top || n === this.top) return false;
      if (n.collider) return true;
      const r = this.rel(n);
      const big = Math.max(r.s.x, r.s.y * ((n.kind === 'cylinder' || n.kind === 'capsule') ? 2 : 1), r.s.z);
      return big >= 0.18 || n.kind === 'plane';
    }

    addCollider(n) {
      const C = this.C;
      const r = this.rel(n);
      const b = new C.Body({ mass: 0, type: C.Body.KINEMATIC });
      b.addShape(this.shapeFor(n, r.s));
      b.position.set(r.p.x, r.p.y, r.p.z);
      b.quaternion.set(r.q.x, r.q.y, r.q.z, r.q.w);
      b.userData = { node: n, last: r.p.clone() };
      n.colBody = b;
      this.world.addBody(b);
      this.cols.add(n);
    }

    addDynamic(n, mass, grav) {
      const C = this.C;
      if (n.colBody) this.removeCol(n);
      const r = this.rel(n);
      const b = new C.Body({ mass: Math.max(0.01, mass) });
      b.addShape(this.shapeFor(n, r.s));
      b.position.set(r.p.x, r.p.y, r.p.z);
      b.quaternion.set(r.q.x, r.q.y, r.q.z, r.q.w);
      b.linearDamping = 0.05;
      b.angularDamping = 0.08;
      b.userData = { node: n, grav: !!grav };
      n.body = b;
      this.world.addBody(b);
      this.dyn.add(n);
      this.pending.delete(n);
    }

    removeCol(n) {
      if (n.colBody) { this.world.removeBody(n.colBody); n.colBody = null; }
      this.cols.delete(n);
    }

    remove(n) {
      this.removeCol(n);
      if (n.body) { this.world.removeBody(n.body); n.body = null; }
      this.dyn.delete(n);
      this.pending.delete(n);
    }

    // vetor do sistema global da Unity -> espaco da simulacao
    toSim(x, y, z) {
      this.top.obj.updateWorldMatrix(true, false);
      this.top.obj.getWorldQuaternion(vq);
      return new THREE.Vector3(x, y, -z).applyQuaternion(vq.invert());
    }
    fromSim(v) {
      this.top.obj.getWorldQuaternion(vq);
      const w = new THREE.Vector3(v.x, v.y, v.z).applyQuaternion(vq);
      return [w.x, w.y, -w.z];
    }

    teleport(n) {
      const b = n.body;
      if (!b) return;
      W.applyMatrix(n);
      const r = this.rel(n);
      b.position.set(r.p.x, r.p.y, r.p.z);
      b.quaternion.set(r.q.x, r.q.y, r.q.z, r.q.w);
      if (b.type !== this.C.Body.KINEMATIC) b.wakeUp();
    }

    step(dt) {
      W.scene.updateMatrixWorld();
      invTop.copy(this.top.obj.matrixWorld).invert();
      // novos objetos viram colisores
      if (this.pending.size) {
        for (const n of this.pending) {
          if (!n.destroyed && isActiveChain(n) && this.eligible(n)) this.addCollider(n);
        }
        this.pending.clear();
      }
      // colisores que se mexem (maos, bots...) acompanham o objeto
      for (const n of this.cols) {
        const b = n.colBody;
        if (!b) continue;
        const on = isActiveChain(n);
        if (!on) { if (b.world) this.world.removeBody(b); continue; }
        if (!b.world) this.world.addBody(b);
        const r = this.rel(n, false);
        const last = b.userData.last;
        const dx = r.p.x - last.x, dy = r.p.y - last.y, dz = r.p.z - last.z;
        if (dx * dx + dy * dy + dz * dz > 1e-8 || Math.abs(b.quaternion.w - r.q.w) > 1e-6) {
          b.velocity.set(dx / dt, dy / dt, dz / dt);
          b.position.set(r.p.x, r.p.y, r.p.z);
          b.quaternion.set(r.q.x, r.q.y, r.q.z, r.q.w);
          last.copy(r.p);
        } else if (b.velocity.lengthSquared() > 0) {
          b.velocity.set(0, 0, 0);
        }
      }
      // corpos dinamicos: ativos?
      for (const n of this.dyn) {
        const b = n.body;
        const on = isActiveChain(n);
        if (!on && b.world) this.world.removeBody(b);
        else if (on && !b.world) this.world.addBody(b);
        if (b.type === this.C.Body.KINEMATIC) this.teleport(n);
        if (b.userData.grav === false) b.applyForce(new this.C.Vec3(0, 9.81 * b.mass, 0));
      }
      this.world.step(1 / 60, dt, 3);
      // devolve as poses para os objetos (no sistema da Unity)
      for (const n of this.dyn) {
        const b = n.body;
        if (!b.world || b.type === this.C.Body.KINEMATIC) continue;
        if (b.sleepState === this.C.Body.SLEEPING) continue;
        let p = new THREE.Vector3(b.position.x, b.position.y, b.position.z);
        let q = new THREE.Quaternion(b.quaternion.x, b.quaternion.y, b.quaternion.z, b.quaternion.w);
        if (n.parent && n.parent !== this.top) {
          // pai intermediario: converte para o espaco local do pai
          const pr = this.rel(n.parent);
          const inv = new THREE.Matrix4().compose(pr.p, pr.q, pr.s).invert();
          const m = new THREE.Matrix4().compose(p, q, new THREE.Vector3(1, 1, 1)).premultiply(inv);
          m.decompose(p, q, vs);
        }
        n.pos[0] = p.x; n.pos[1] = p.y; n.pos[2] = -p.z;
        const e = W.quatToEuler(-q.x, -q.y, q.z, q.w);
        n.rot[0] = e[0]; n.rot[1] = e[1]; n.rot[2] = e[2];
        n.dirty = true;
      }
      W.applyAllDirty();
    }

    onCreate(n) { this.pending.add(n); }
    onActive(n) { /* tratado no step (isActiveChain) */ }
    onReparent(n) {
      if (n.colBody) { this.removeCol(n); this.pending.add(n); }
    }
  }

  function ensure(n) {
    if (!W.physics) {
      const top = topOf(n);
      W.physics = new Physics(top);
    }
    return W.physics;
  }

  PB.register = function () {
    const { reg, lua } = W;
    const node = (Ls) => W.nodes.get(lua.int(Ls, 1));
    reg('H_addbody', (Ls) => {
      const n = node(Ls); if (!n) return;
      W.applyAllDirty();
      const P = ensure(n);
      P.addDynamic(n, lua.num(Ls, 2), lua.bool(Ls, 3));
    });
    reg('H_collider', (Ls) => {
      const n = node(Ls); if (!n) return;
      n.collider = lua.int(Ls, 2);
      n.colliderR = lua.num(Ls, 3) || 0.5;
      if (W.physics) {
        if (n.body) {
          // troca a forma do corpo dinamico
          const P = W.physics, b = n.body;
          while (b.shapes.length) b.removeShape(b.shapes[0]);
          b.addShape(P.shapeFor(n, P.rel(n).s));
        } else {
          W.physics.removeCol(n);
          W.physics.pending.add(n);
        }
      }
    });
    reg('H_setvel', (Ls) => {
      const n = node(Ls); if (!n || !n.body) return;
      const v = W.physics.toSim(lua.num(Ls, 2), lua.num(Ls, 3), lua.num(Ls, 4));
      n.body.velocity.set(v.x, v.y, v.z);
      n.body.wakeUp();
    });
    reg('H_getvel', (Ls) => {
      const n = node(Ls);
      const v = n && n.body ? W.physics.fromSim(n.body.velocity) : [0, 0, 0];
      lua.pushN(Ls, v[0]); lua.pushN(Ls, v[1]); lua.pushN(Ls, v[2]);
      return 3;
    });
    reg('H_setang', (Ls) => {
      const n = node(Ls); if (!n || !n.body) return;
      // vetor axial: no espelho em z, x e y trocam de sinal
      const v = W.physics.toSim(-lua.num(Ls, 2), -lua.num(Ls, 3), -lua.num(Ls, 4));
      n.body.angularVelocity.set(v.x, v.y, v.z);
    });
    reg('H_getang', (Ls) => {
      const n = node(Ls);
      const v = n && n.body ? W.physics.fromSim(n.body.angularVelocity) : [0, 0, 0];
      lua.pushN(Ls, -v[0]); lua.pushN(Ls, -v[1]); lua.pushN(Ls, -v[2]);
      return 3;
    });
    reg('H_kin', (Ls) => {
      const n = node(Ls); if (!n || !n.body) return;
      const C = W.CANNON;
      if (lua.bool(Ls, 2)) {
        n.body.type = C.Body.KINEMATIC;
        n.body.velocity.set(0, 0, 0); n.body.angularVelocity.set(0, 0, 0);
      } else {
        n.body.type = C.Body.DYNAMIC;
        n.body.updateMassProperties();
        n.body.wakeUp();
      }
    });
    reg('H_force', (Ls) => {
      const n = node(Ls); if (!n || !n.body) return;
      const v = W.physics.toSim(lua.num(Ls, 2), lua.num(Ls, 3), lua.num(Ls, 4));
      const imp = lua.int(Ls, 5) === 1;
      const C = W.CANNON;
      if (imp) n.body.applyImpulse(new C.Vec3(v.x, v.y, v.z));
      else n.body.applyForce(new C.Vec3(v.x, v.y, v.z));
      n.body.wakeUp();
    });
    reg('H_grav', (Ls) => { const n = node(Ls); if (n && n.body) n.body.userData.grav = lua.bool(Ls, 2); });
    reg('H_mass', (Ls) => {
      const n = node(Ls); if (!n || !n.body) return;
      n.body.mass = Math.max(0.01, lua.num(Ls, 2)); n.body.updateMassProperties();
    });
  };
})();
