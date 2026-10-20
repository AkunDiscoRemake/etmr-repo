# Versão HTML pura (navegador)

Os 3 jogos — **BONELAB Remake**, **SUPERHOT Remake** e **RE:Steal A Brainrot VR** — rodando
direto no navegador, cada um num **único arquivo .html** (sem instalar nada, sem servidor).

| Jogo | Arquivo |
|---|---|
| BONELAB Remake | `dist/BonelabRemake.html` |
| SUPERHOT Remake | `dist/SuperhotRemake.html` |
| RE:Steal A Brainrot VR | `dist/StealABrainrotVR.html` |

## Mesmo jogo, sem diferença
Os scripts Lua dos jogos são **exatamente os mesmos** do APK (sem nenhuma alteração).
O arquivo HTML traz junto um Lua 5.4 em WebAssembly (wasmoon) e uma reimplementação da
EMRAPI (`runtime/`) em cima de three.js (gráficos), cannon-es (física), WebAudio (som
3D) e Photon JS (online). Texturas e sons vão embutidos no HTML.

## Como jogar
Abra o `.html` no Chrome/Edge/Firefox (PC ou celular) e escolha:
- **PC** — mouse olha (clique para prender), WASD anda, botão direito/E pega, botão
  esquerdo atira/usa, Q/F mão esquerda, Espaço = A, V/C soco, roda do mouse estica as
  mãos, Tab/M = menu. Joy-Con/controle Bluetooth funciona direto (Gamepad API).
- **VR Box** — celular no óculos: tela dividida, giroscópio para olhar, toque/A clica.
- **Óculos VR (WebXR)** — Quest etc., com controles ou hand tracking.
- Opção **📷 Mãos pela câmera**: hand tracking pela câmera (MediaPipe; baixa o modelo,
  precisa de internet).

## Online (Brainrot)
Só online, sem bots, igual ao APK — usa o Photon App ID do `app.json`, precisa de
internet. As salas da versão web usam um `appVersion` próprio (`web-...`), então
jogadores do navegador jogam com jogadores do navegador (não cruza com o APK).

## Gerar de novo
```
python3 web/build.py            # os 3
python3 web/build.py brainrot   # só um
```
Testes (Playwright): `node web/test_web.js web/dist/SuperhotRemake.html out.png` e
`node web/test_mp_web.js web/dist/StealABrainrotVR.html` (duas abas online).
