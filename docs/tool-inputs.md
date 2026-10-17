# Nimbus — ferramentas e inputs

Opções de cada ferramenta do Quick Drop. Os rótulos abaixo estão em português;
a UI é escrita em inglês. A opção é escolhida numa lista depois do drop (setas,
Enter confirma, Esc cancela); o padrão vem das Preferências.

### Compress Images (`to-webp`)

- Arquivo: imagem (vários)
- Compressão: baixa (melhor qualidade), alta (menor arquivo) ou sem perda
- Saída: WebP

### Compress Videos (`to-webm`)

- Arquivo: vídeo (vários)
- Compressão: baixa, alta ou sem perda
- Saída: WebM (VP9 + Opus, via ffmpeg embutido)

### Favicon Generator (`ico`)

- Arquivo: imagem (um)
- Margem de segurança: sem margem ou com margem segura
- Saída: zip com `favicon.ico` e os PNGs

### Auto Crop (`trim-image`)

- Arquivo: imagem (vários), sem opções
- Saída: PNG

### Image Converter (`convert`)

- Arquivo: imagem (vários)
- Formato de saída: `png`, `jpg` ou `webp`

### Video Converter (`video-convert`)

- Arquivo: vídeo (vários)
- Formato de saída: `mp4`, `mov` (H.264 via AVFoundation) ou `webm` (VP9, CRF 28)
