// Ported from nimbus/app/api/tools/web/policy-generator/route.ts, minus
// session/quota. The generated policy/terms text itself is left exactly as
// the original route produces it (Portuguese boilerplate legal copy) — only
// the two user-facing error messages are translated, per the porting rule.
async function handlePolicyGenerator(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const companyName = data.get('companyName')
  const companyUrl = data.get('companyUrl')

  if (!companyName || !companyUrl) {
    return Response.json({ error: 'companyName and companyUrl are required' }, { status: 400 })
  }

  try {
    const nimbusTxt = `gerado por: Nimbus (https://nimbus.com.br)`
    const nimbusHtml = `gerado por: <a href="https://nimbus.com.br" style="color: #007bff; text-decoration: none;">Nimbus</a>`
    const nimbusReact = `gerado por: <a href="https://nimbus.com.br" target="_blank" rel="noopener noreferrer" className="text-blue-600 dark:text-blue-400 hover:underline">Nimbus</a>`

    /* =========================================
       TEXT FORMAT
       ========================================= */
    const privacyText = `Política de Privacidade

A sua privacidade é importante para nós. É política do ${companyName} respeitar a sua privacidade em relação a qualquer informação sua que possamos coletar no site ${companyUrl}.

Solicitamos informações pessoais apenas quando realmente precisamos delas para lhe fornecer um serviço. Fazemo-lo por meios justos e legais, com o seu conhecimento e consentimento. Também informamos por que estamos coletando e como será usado.

Apenas retemos as informações coletadas pelo tempo necessário para fornecer o serviço solicitado. Quando armazenamos dados, os protegemos dentro de meios comercialmente aceitáveis ​​para evitar perdas e roubos, bem como acesso, divulgação, cópia, uso ou modificação não autorizados.

Não compartilhamos informações de identificação pessoal publicamente ou com terceiros, exceto quando exigido por lei.

O nosso site pode ter links para sites externos que não são operados por nós. Esteja ciente de que não temos controle sobre o conteúdo e práticas desses sites e não podemos aceitar responsabilidade por suas respectivas políticas de privacidade.

Você é livre para recusar a nossa solicitação de informações pessoais, entendendo que talvez não possamos fornecer alguns dos serviços desejados.

O uso continuado de nosso site será considerado como aceitação de nossas práticas em torno de privacidade e informações pessoais. Se você tiver alguma dúvida sobre como lidamos com dados do usuário e informações pessoais, entre em contacto connosco.

${nimbusTxt}`

    const termsText = `Termos e Condições

1. Termos
Ao acessar ao site ${companyName}, concorda em cumprir estes termos de serviço, todas as leis e regulamentos aplicáveis ​​e concorda que é responsável pelo cumprimento de todas as leis locais aplicáveis. Se você não concordar com algum desses termos, está proibido de usar ou acessar este site. Os materiais contidos neste site são protegidos pelas leis de direitos autorais e marcas comerciais aplicáveis.

2. Uso de Licença
É concedida permissão para baixar temporariamente uma cópia dos materiais (informações ou software) no site ${companyName}, apenas para visualização transitória pessoal e não comercial. Esta é a concessão de uma licença, não uma transferência de título e, sob esta licença, você não pode:
- modificar ou copiar os materiais;
- usar os materiais para qualquer finalidade comercial ou para exibição pública (comercial ou não comercial);
- tentar descompilar ou fazer engenharia reversa de qualquer software contido no site ${companyName};
- remover quaisquer direitos autorais ou outras notações de propriedade dos materiais; ou
- transferir os materiais para outra pessoa ou 'espelhe' os materiais em qualquer outro servidor.

Esta licença será automaticamente rescindida se você violar alguma dessas restrições e poderá ser rescindida por ${companyName} a qualquer momento. Ao encerrar a visualização desses materiais ou após o término desta licença, você deve apagar todos os materiais baixados em sua posse, seja em formato eletrónico ou impresso.

3. Isenção de responsabilidade
Os materiais no site da ${companyName} são fornecidos 'como estão'. ${companyName} não oferece garantias, expressas ou implícitas, e, por este meio, isenta e nega todas as outras garantias, incluindo, sem limitação, garantias implícitas ou condições de comercialização, adequação a um fim específico ou não violação de propriedade intelectual ou outra violação de direitos.

4. Limitações
Em nenhum caso o ${companyName} ou seus fornecedores serão responsáveis ​​por quaisquer danos (incluindo, sem limitação, danos por perda de dados ou lucro ou devido a interrupção dos negócios) decorrentes do uso ou da incapacidade de usar os materiais em ${companyName}, mesmo que ${companyName} ou um representante autorizado da ${companyName} tenha sido notificado oralmente ou por escrito da possibilidade de tais danos.

5. Precisão dos materiais
Os materiais exibidos no site da ${companyName} podem incluir erros técnicos, tipográficos ou fotográficos. ${companyName} não garante que qualquer material em seu site seja preciso, completo ou atual. ${companyName} pode fazer alterações nos materiais contidos em seu site a qualquer momento, sem aviso prévio.

6. Links
O ${companyName} não analisou todos os sites vinculados ao seu site e não é responsável pelo conteúdo de nenhum site vinculado. A inclusão de qualquer link não implica endosso por ${companyName} do site. O uso de qualquer site vinculado é por conta e risco do usuário.

7. Modificações
O ${companyName} pode revisar estes termos de serviço do site a qualquer momento, sem aviso prévio. Ao usar este site, você concorda em ficar vinculado à versão atual desses termos de serviço.

8. Lei aplicável
Estes termos e condições são regidos e interpretados de acordo com as leis e você se submete irrevogavelmente à jurisdição exclusiva dos tribunais naquele estado ou localidade.

${nimbusTxt}`

    /* =========================================
       HTML FORMAT
       ========================================= */
    const privacyHtml = `<div style="font-family: sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 20px;">
  <h1 style="color: #000; font-size: 24px; margin-bottom: 16px;">Política de Privacidade</h1>
  <p style="margin-bottom: 16px;">A sua privacidade é importante para nós. É política do <strong>${companyName}</strong> respeitar a sua privacidade em relação a qualquer informação sua que possamos coletar no site <a href="${companyUrl}" style="color: #007bff; text-decoration: none;">${companyUrl}</a>.</p>
  <p style="margin-bottom: 16px;">Solicitamos informações pessoais apenas quando realmente precisamos delas para lhe fornecer um serviço. Fazemo-lo por meios justos e legais, com o seu conhecimento e consentimento. Também informamos por que estamos coletando e como será usado.</p>
  <p style="margin-bottom: 16px;">Apenas retemos as informações coletadas pelo tempo necessário para fornecer o serviço solicitado. Quando armazenamos dados, os protegemos dentro de meios comercialmente aceitáveis ​​para evitar perdas e roubos, bem como acesso, divulgação, cópia, uso ou modificação não autorizados.</p>
  <p style="margin-bottom: 16px;">Não compartilhamos informações de identificação pessoal publicamente ou com terceiros, exceto quando exigido por lei.</p>
  <p style="margin-bottom: 16px;">O nosso site pode ter links para sites externos que não são operados por nós. Esteja ciente de que não temos controle sobre o conteúdo e práticas desses sites e não podemos aceitar responsabilidade por suas respectivas políticas de privacidade.</p>
  <p style="margin-bottom: 16px;">Você é livre para recusar a nossa solicitação de informações pessoais, entendendo que talvez não possamos fornecer alguns dos serviços desejados.</p>
  <p style="margin-bottom: 24px;">O uso continuado de nosso site será considerado como aceitação de nossas práticas em torno de privacidade e informações pessoais. Se você tiver alguma dúvida sobre como lidamos com dados do usuário e informações pessoais, entre em contacto connosco.</p>
  <hr style="border: 0; border-top: 1px solid #eee; margin-bottom: 16px;" />
  <p style="font-size: 14px; color: #666; text-align: center;">${nimbusHtml}</p>
</div>`

    const termsHtml = `<div style="font-family: sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 20px;">
  <h1 style="color: #000; font-size: 24px; margin-bottom: 20px;">Termos e Condições</h1>

  <h2 style="color: #111; font-size: 18px; margin-top: 24px; margin-bottom: 12px;">1. Termos</h2>
  <p style="margin-bottom: 16px;">Ao acessar ao site <strong><a href="${companyUrl}" style="color: #007bff; text-decoration: none;">${companyName}</a></strong>, concorda em cumprir estes termos de serviço, todas as leis e regulamentos aplicáveis ​​e concorda que é responsável pelo cumprimento de todas as leis locais aplicáveis. Se você não concordar com algum desses termos, está proibido de usar ou acessar este site. Os materiais contidos neste site são protegidos pelas leis de direitos autorais e marcas comerciais aplicáveis.</p>

  <h2 style="color: #111; font-size: 18px; margin-top: 24px; margin-bottom: 12px;">2. Uso de Licença</h2>
  <p style="margin-bottom: 16px;">É concedida permissão para baixar temporariamente uma cópia dos materiais (informações ou software) no site ${companyName}, apenas para visualização transitória pessoal e não comercial. Esta é a concessão de uma licença, não uma transferência de título e, sob esta licença, você não pode:</p>
  <ul style="margin-bottom: 16px; padding-left: 20px;">
    <li style="margin-bottom: 8px;">modificar ou copiar os materiais;</li>
    <li style="margin-bottom: 8px;">usar os materiais para qualquer finalidade comercial ou para exibição pública (comercial ou não comercial);</li>
    <li style="margin-bottom: 8px;">tentar descompilar ou fazer engenharia reversa de qualquer software contido no site ${companyName};</li>
    <li style="margin-bottom: 8px;">remover quaisquer direitos autorais ou outras notações de propriedade dos materiais; ou</li>
    <li style="margin-bottom: 8px;">transferir os materiais para outra pessoa ou 'espelhe' os materiais em qualquer outro servidor.</li>
  </ul>
  <p style="margin-bottom: 16px;">Esta licença será automaticamente rescindida se você violar alguma dessas restrições e poderá ser rescindida por ${companyName} a qualquer momento. Ao encerrar a visualização desses materiais ou após o término desta licença, você deve apagar todos os materiais baixados em sua posse, seja em formato eletrónico ou impresso.</p>

  <h2 style="color: #111; font-size: 18px; margin-top: 24px; margin-bottom: 12px;">3. Isenção de responsabilidade</h2>
  <p style="margin-bottom: 16px;">Os materiais no site da ${companyName} são fornecidos 'como estão'. ${companyName} não oferece garantias, expressas ou implícitas, e, por este meio, isenta e nega todas as outras garantias, incluindo, sem limitação, garantias implícitas ou condições de comercialização, adequação a um fim específico ou não violação de propriedade intelectual ou outra violação de direitos.</p>

  <h2 style="color: #111; font-size: 18px; margin-top: 24px; margin-bottom: 12px;">4. Limitações</h2>
  <p style="margin-bottom: 16px;">Em nenhum caso o ${companyName} ou seus fornecedores serão responsáveis ​​por quaisquer danos (incluindo, sem limitação, danos por perda de dados ou lucro ou devido a interrupção dos negócios) decorrentes do uso ou da incapacidade de usar os materiais em ${companyName}, mesmo que ${companyName} ou um representante autorizado da ${companyName} tenha sido notificado oralmente ou por escrito da possibilidade de tais danos.</p>

  <h2 style="color: #111; font-size: 18px; margin-top: 24px; margin-bottom: 12px;">5. Precisão dos materiais</h2>
  <p style="margin-bottom: 16px;">Os materiais exibidos no site da ${companyName} podem incluir erros técnicos, tipográficos ou fotográficos. ${companyName} não garante que qualquer material em seu site seja preciso, completo ou atual. ${companyName} pode fazer alterações nos materiais contidos em seu site a qualquer momento, sem aviso prévio.</p>

  <h2 style="color: #111; font-size: 18px; margin-top: 24px; margin-bottom: 12px;">6. Links</h2>
  <p style="margin-bottom: 16px;">O ${companyName} não analisou todos os sites vinculados ao seu site e não é responsável pelo conteúdo de nenhum site vinculado. A inclusão de qualquer link não implica endosso por ${companyName} do site. O uso de qualquer site vinculado é por conta e risco do usuário.</p>

  <h2 style="color: #111; font-size: 18px; margin-top: 24px; margin-bottom: 12px;">7. Modificações</h2>
  <p style="margin-bottom: 16px;">O ${companyName} pode revisar estes termos de serviço do site a qualquer momento, sem aviso prévio. Ao usar este site, você concorda em ficar vinculado à versão atual desses termos de serviço.</p>

  <h2 style="color: #111; font-size: 18px; margin-top: 24px; margin-bottom: 12px;">8. Lei aplicável</h2>
  <p style="margin-bottom: 24px;">Estes termos e condições são regidos e interpretados de acordo com as leis e você se submete irrevogavelmente à jurisdição exclusiva dos tribunais naquele estado ou localidade.</p>

  <hr style="border: 0; border-top: 1px solid #eee; margin-bottom: 16px;" />
  <p style="font-size: 14px; color: #666; text-align: center;">${nimbusHtml}</p>
</div>`

    /* =========================================
       REACT (TAILWIND) FORMAT
       ========================================= */
    const privacyReact = `import React from 'react';

export default function PrivacyPolicy() {
  return (
    <div className="max-w-3xl mx-auto p-6 text-zinc-800 dark:text-zinc-200 leading-relaxed font-sans">
      <h1 className="text-2xl text-black dark:text-white mb-4">Política de Privacidade</h1>

      <p className="mb-4">
        A sua privacidade é importante para nós. É política do <strong className="font-semibold text-black dark:text-white">${companyName}</strong> respeitar a sua privacidade em relação a qualquer informação sua que possamos coletar no site <a href="${companyUrl}" className="text-blue-600 dark:text-blue-400 hover:underline">${companyUrl}</a>.
      </p>

      <p className="mb-4">
        Solicitamos informações pessoais apenas quando realmente precisamos delas para lhe fornecer um serviço. Fazemo-lo por meios justos e legais, com o seu conhecimento e consentimento. Também informamos por que estamos coletando e como será usado.
      </p>

      <p className="mb-4">
        Apenas retemos as informações coletadas pelo tempo necessário para fornecer o serviço solicitado. Quando armazenamos dados, os protegemos dentro de meios comercialmente aceitáveis ​​para evitar perdas e roubos, bem como acesso, divulgação, cópia, uso ou modificação não autorizados.
      </p>

      <p className="mb-4">
        Não compartilhamos informações de identificação pessoal publicamente ou com terceiros, exceto quando exigido por lei.
      </p>

      <p className="mb-4">
        O nosso site pode ter links para sites externos que não são operados por nós. Esteja ciente de que não temos controle sobre o conteúdo e práticas desses sites e não podemos aceitar responsabilidade por suas respectivas políticas de privacidade.
      </p>

      <p className="mb-4">
        Você é livre para recusar a nossa solicitação de informações pessoais, entendendo que talvez não possamos fornecer alguns dos serviços desejados.
      </p>

      <p className="mb-6">
        O uso continuado de nosso site será considerado como aceitação de nossas práticas em torno de privacidade e informações pessoais. Se você tiver alguma dúvida sobre como lidamos com dados do usuário e informações pessoais, entre em contacto connosco.
      </p>

      <hr className="border-zinc-200 dark:border-zinc-800 my-6" />

      <p className="text-sm text-center text-zinc-500 dark:text-zinc-400">
        ${nimbusReact}
      </p>
    </div>
  );
}`

    const termsReact = `import React from 'react';

export default function TermsAndConditions() {
  return (
    <div className="max-w-3xl mx-auto p-6 text-zinc-800 dark:text-zinc-200 leading-relaxed font-sans">
      <h1 className="text-2xl text-black dark:text-white mb-6">Termos e Condições</h1>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-black dark:text-white mb-3">1. Termos</h2>
        <p className="mb-4">
          Ao acessar ao site <strong className="font-semibold text-black dark:text-white"><a href="${companyUrl}" className="text-blue-600 dark:text-blue-400 hover:underline">${companyName}</a></strong>, concorda em cumprir estes termos de serviço, todas as leis e regulamentos aplicáveis ​​e concorda que é responsável pelo cumprimento de todas as leis locais aplicáveis. Se você não concordar com algum desses termos, está proibido de usar ou acessar este site. Os materiais contidos neste site são protegidos pelas leis de direitos autorais e marcas comerciais aplicáveis.
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-black dark:text-white mb-3">2. Uso de Licença</h2>
        <p className="mb-4">
          É concedida permissão para baixar temporariamente uma cópia dos materiais (informações ou software) no site ${companyName}, apenas para visualização transitória pessoal e não comercial. Esta é a concessão de uma licença, não uma transferência de título e, sob esta licença, você não pode:
        </p>
        <ul className="list-disc pl-6 mb-4 space-y-2">
          <li>modificar ou copiar os materiais;</li>
          <li>usar os materiais para qualquer finalidade comercial ou para exibição pública (comercial ou não comercial);</li>
          <li>tentar descompilar ou fazer engenharia reversa de qualquer software contido no site ${companyName};</li>
          <li>remover quaisquer direitos autorais ou outras notações de propriedade dos materiais; ou</li>
          <li>transferir os materiais para outra pessoa ou 'espelhe' os materiais em qualquer outro servidor.</li>
        </ul>
        <p className="mb-4">
          Esta licença será automaticamente rescindida se você violar alguma dessas restrições e poderá ser rescindida por ${companyName} a qualquer momento. Ao encerrar a visualização desses materiais ou após o término desta licença, você deve apagar todos os materiais baixados em sua posse, seja em formato eletrónico ou impresso.
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-black dark:text-white mb-3">3. Isenção de responsabilidade</h2>
        <p className="mb-4">
          Os materiais no site da ${companyName} são fornecidos 'como estão'. ${companyName} não oferece garantias, expressas ou implícitas, e, por este meio, isenta e nega todas as outras garantias, incluindo, sem limitação, garantias implícitas ou condições de comercialização, adequação a um fim específico ou não violação de propriedade intelectual ou outra violação de direitos.
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-black dark:text-white mb-3">4. Limitações</h2>
        <p className="mb-4">
          Em nenhum caso o ${companyName} ou seus fornecedores serão responsáveis ​​por quaisquer danos (incluindo, sem limitação, danos por perda de dados ou lucro ou devido a interrupção dos negócios) decorrentes do uso ou da incapacidade de usar os materiais em ${companyName}, mesmo que ${companyName} ou um representante autorizado da ${companyName} tenha sido notificado oralmente ou por escrito da possibilidade de tais danos.
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-black dark:text-white mb-3">5. Precisão dos materiais</h2>
        <p className="mb-4">
          Os materiais exibidos no site da ${companyName} podem incluir erros técnicos, tipográficos ou fotográficos. ${companyName} não garante que qualquer material em seu site seja preciso, completo ou atual. ${companyName} pode fazer alterações nos materiais contidos em seu site a qualquer momento, sem aviso prévio.
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-black dark:text-white mb-3">6. Links</h2>
        <p className="mb-4">
          O ${companyName} não analisou todos os sites vinculados ao seu site e não é responsável pelo conteúdo de nenhum site vinculado. A inclusão de qualquer link não implica endosso por ${companyName} do site. O uso de qualquer site vinculado é por conta e risco do usuário.
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-black dark:text-white mb-3">7. Modificações</h2>
        <p className="mb-4">
          O ${companyName} pode revisar estes termos de serviço do site a qualquer momento, sem aviso prévio. Ao usar este site, você concorda em ficar vinculado à versão atual desses termos de serviço.
        </p>
      </section>

      <section className="mb-8">
        <h2 className="text-lg font-semibold text-black dark:text-white mb-3">8. Lei aplicável</h2>
        <p className="mb-4">
          Estes termos e condições são regidos e interpretados de acordo com as leis e você se submete irrevogavelmente à jurisdição exclusiva dos tribunais naquele estado ou localidade.
        </p>
      </section>

      <hr className="border-zinc-200 dark:border-zinc-800 my-6" />

      <p className="text-sm text-center text-zinc-500 dark:text-zinc-400">
        ${nimbusReact}
      </p>
    </div>
  );
}`

    return Response.json({
      privacyPolicy: {
        text: privacyText,
        html: privacyHtml,
        react: privacyReact,
      },
      termsOfConditions: {
        text: termsText,
        html: termsHtml,
        react: termsReact,
      },
    })
  } catch (error) {
    console.error('Policy generator error:', error)
    return Response.json({ error: 'Internal error processing the request' }, { status: 500 })
  }
}

export function registerPolicyGenerator(registerRoute) {
  registerRoute('POST', '/api/tools/web/policy-generator', handlePolicyGenerator)
}
