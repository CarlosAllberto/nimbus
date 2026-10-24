<p align="center">
  <img src="docs/assets/icon.png" alt="Ícone do Nimbus" width="128" height="128">
</p>

<h1 align="center">Nimbus</h1>

<p align="center"><b>Comprima e converta imagens e vídeos direto da barra de menus do macOS.</b></p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-lightgrey?style=flat-square">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-orange?style=flat-square">
  <img alt="Interface nativa" src="https://img.shields.io/badge/interface-nativa-blue?style=flat-square">
  <a href="LICENSE"><img alt="Licença MIT" src="https://img.shields.io/badge/licen%C3%A7a-MIT-blue?style=flat-square"></a>
  <a href="https://github.com/CarlosAllberto/nimbus/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/CarlosAllberto/nimbus/ci.yml?branch=main&style=flat-square&label=CI"></a>
</p>

<p align="center">
  <a href="#recursos">Recursos</a> &bull;
  <a href="#instalação">Instalação</a> &bull;
  <a href="#uso">Uso</a> &bull;
  <a href="#compilar-do-código-fonte">Compilar do código-fonte</a> &bull;
  <a href="#como-funciona">Como funciona</a>
</p>

<p align="center"><a href="README.md">English</a> &bull; Português</p>

Arraste um arquivo, escolha uma opção e pronto. O Nimbus é um app de barra de menus para macOS que comprime e converte imagens e vídeos em um pequeno popup que desliza da borda da tela. Tudo roda no seu Mac, sem conta e sem upload.

![Quick Drop do Nimbus: as ferramentas, as opções de compressão e os resultados](docs/assets/quick-drop.jpg)

## Recursos

- **Comprimir Imagens**: reduz imagens com compressão baixa, alta ou sem perdas, ou converte para WebP.
- **Comprimir Vídeos**: recodifica um vídeo em um WebM menor.
- **Gerar Favicon**: transforma uma imagem em um favicon de navegador (`.ico`).
- **Corte Automático**: corta uma imagem até o conteúdo.
- **Converter Imagem**: converte entre PNG, JPG e WebP.
- **Conversor Vídeo**: converte entre MP4, MOV e WebM.
- Progresso por arquivo, com o tamanho antes e depois e a porcentagem economizada.
- Os resultados vão para `~/Nimbus`; os originais não são alterados.
- Pensado para o teclado: setas para escolher, Return para executar, Esc para cancelar.
- Disponível em inglês e português do Brasil.

## Instalação

Baixe o `Nimbus.zip` mais recente na [página de releases](https://github.com/CarlosAllberto/nimbus/releases/tag/latest), descompacte e mova o `Nimbus.app` para `/Applications`.

> [!NOTE]
> Os builds ainda não são assinados com um Apple Developer ID. Na primeira abertura, clique com o botão direito no `Nimbus.app` e escolha **Abrir**, ou libere o app em **Ajustes do Sistema > Privacidade e Segurança**.

Requer macOS 14 ou mais recente. Depois de instalado, o Nimbus se atualiza sozinho pelo Sparkle.

## Uso

1. Abra o Quick Drop com **⌥Q**, pelo ícone na barra de menus, ou arrastando arquivos com **⌘** pressionado.
2. Solte os arquivos sobre uma ferramenta.
3. Escolha uma opção, como o nível de compressão, e aperte Return.
4. Encontre os resultados em `~/Nimbus`.

Segure **⌘** enquanto arrasta para abrir o popup de qualquer lugar; ao soltar o **⌘**, o popup desliza para fora de novo. Arrastar sem **⌘** nunca aciona o Nimbus.

O popup fica junto à borda da tela que você escolher nas Preferências (topo, esquerda, base ou direita). As Preferências também definem a opção padrão de cada ferramenta e se o Nimbus abre no login.

## Compilar do código-fonte

Você precisa do Xcode 26 ou mais recente.

```sh
git clone https://github.com/CarlosAllberto/nimbus.git
cd nimbus
swift run Nimbus
```

O `swift build` gera só um executável, o que basta para desenvolver. Para obter o `.app` completo, com ícone, recursos e Sparkle, abra o `Nimbus.xcodeproj` no Xcode e rode o scheme `Nimbus`.

Outros comandos:

```sh
make lint   # SwiftLint, se estiver instalado
make ci     # lint + build, igual ao CI
```

## Como funciona

O Nimbus é um app nativo em Swift, sem processo auxiliar nem web view. As imagens usam ImageIO e libwebp, e os vídeos usam AVFoundation. A exceção é a saída em WebM, que usa um build LGPL do `ffmpeg` embutido no app (VP9 e Opus). Para recompilá-lo, use `Tools/build-ffmpeg.sh`.

O mapa dos arquivos do código está em [`docs/memory/memory.md`](docs/memory/memory.md), e as notas para agentes de código estão em [`AGENTS.md`](AGENTS.md).

## Licença

[MIT](LICENSE). O `ffmpeg` embutido é um build LGPL e mantém a própria licença.
