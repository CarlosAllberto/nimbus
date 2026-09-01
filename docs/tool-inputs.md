# Nimbus — ferramentas e inputs

Fonte da verdade dos campos de entrada de cada ferramenta. Espelha a nota
Maestri `nimbus-ferramentas-e-inputs`. Os rótulos abaixo estão em português;
a UI é escrita em inglês.

## Web

### Compress Images (`to-webp`)

- Arquivo: imagem
- Operação: converter para WebP ou comprimir imagem
- Qualidade: `sem-perdas`, `lustroso` ou `perda`

### Copy Generator

- Usar arquivo de briefing: ligado/desligado
- Arquivo de briefing: `.txt`, `.docx` ou `.pdf`
- Descrição do site
- Páginas (uma ou mais):
  - Título da página
  - Seções
- Observações adicionais

### Favicon Generator (`ico`)

- Arquivo: imagem
- Margem de segurança: ligada/desligada

### Compress Videos (`to-webm`)

- Arquivo: vídeo
- Qualidade: `lustroso`, `perda` ou `sem-perdas`

### WHOIS Scan

- Domínio

### DNS Check

- Domínio ou host
- Tipo de registro DNS: `A`, `AAAA`, `CNAME`, `MX`, `TXT`, `NS`, `SOA` ou `CAA`

### Site Speed

- URL
- Estratégia: `mobile` ou `desktop`

### WordPress Inspector

- URL

### Policy Generator

- Nome da empresa
- URL da empresa ou site

### Responsive Font Clamp

- Largura mínima do viewport
- Largura máxima do viewport
- Fonte desktop (aceita múltiplos valores)
- Fonte mobile ou modo automático
- Unidade: `px` ou `rem`

## Studio

### Device Wrapper

- Arquivo: imagem
- Sistema/dispositivo: `macos` ou `windows`
- Fundo: `transparent` ou `image`
- Imagem de fundo (quando o fundo for `image`)

### Trim Image

- Arquivo: imagem

### Convert

- Arquivo: imagem
- Formato de saída: `png`, `jpg` ou `webp`

### Resize Image (`resize`)

- Arquivo: imagem
- Dimensão: largura ou altura
- Valor da dimensão

### Resize Video (`resize-video`)

- Arquivo: vídeo
- Dimensão: largura ou altura
- Valor da dimensão

## Code

### HTML Minify

- HTML
- Ação: `minify` ou `unminify`

### JS Minify

- JavaScript
- Ação: `minify` ou `unminify`

### JSON Creator

- Estrutura: objeto ou array
- Propriedades:
  - Chave/nome
  - Valor
  - Tipo: `string`, `number`, `boolean`, `null`, `object` ou `array`

## Tools

### Password Generator

- Base/prefixo
- Comprimento: de `8` a `64`
- Converter letras em números: ligado/desligado
- Incluir maiúsculas: ligado/desligado

### Color Convert

- Cor

### Palette From Image

- Arquivo: imagem
- Quantidade de cores

### Contrast Check

- Cor do foreground
- Cor do background

### WhatsApp Link

- Telefone
- Mensagem
- Destino/formato: `wa.me`, `api` ou `web`

### Contract PDF

- Cliente:
  - Nome
  - CPF
  - E-mail
  - Telefone
  - Endereço
- Contratada:
  - Razão social ou nome da empresa
  - CNPJ
  - Endereço
- Foro:
  - Cidade
  - UF
- Serviço/contrato:
  - Tipo ou descrição do serviço
  - Prazo em semanas
  - Valor
- Assinatura:
  - Local/data
  - Signatário 1
  - Signatário 2

### QR Code

- Conteúdo/dados
- Ícone central opcional: imagem ou SVG

### Font Convert

- Arquivo de fonte: `.ttf`, `.otf`, `.woff`, `.woff2` ou `.eot`
- Formato de saída: `ttf`, `otf`, `woff`, `woff2` ou `eot`
