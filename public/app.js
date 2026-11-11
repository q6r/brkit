/* Kit Brasil playground: validate, generate and watch the checksums being computed.
 *
 * A classic script on top of the Aurora UI kit (aurora.js). The page is built by Aurora.shell (navigation rail, top
 * bar, tool tabs, status bar); this file fills it. It talks to the JSON API of the same origin and never builds HTML
 * from data: every string reaches the page through textContent (Aurora.el). No inline script or style is used, so
 * the page works under the server's Content-Security-Policy.
 *
 * Sections: 1 texts (PT/EN) · 2 helpers · 3 API client · 4 stepper · 5 explainers · 6 shared panels · 7 document
 * tabs · 8 PIX tab · 9 fake people tab · 10 shell (rail, bars, router, language, command palette). */
(function () {
  'use strict';

  const { el, svg, icon } = Aurora;
  Aurora.init();

  /* ════════════════════════════ 1. texts ════════════════════════════
   * One dictionary per language with exactly the same keys (test/playground_test.rb checks it). {name} marks a
   * parameter. The JSON between the markers is parsed by that test, so keep it strict JSON. */
  const MESSAGES = /* i18n:start */ {
    "pt": {
      "app.title": "Kit Brasil · brkit",
      "app.eyebrow": "Playground interativo",
      "app.lead": "Valide, gere e entenda documentos brasileiros. Cada dígito verificador é calculado diante de você, passo a passo.",
      "app.chip.api": "API real em /api/v1",
      "app.chip.offline": "Funciona offline",
      "app.chip.deps": "Sem dependências",
      "live.connecting": "Conectando…",
      "live.ok": "API v{version}",
      "live.offline": "API indisponível",
      "top.lang": "Idioma",
      "tabs.label": "Ferramentas",
      "rail.playground": "Playground",
      "rail.api": "API (OpenAPI)",
      "rail.palette": "Paleta de comandos",
      "status.version": "brkit {version}",
      "status.license": "Licença MIT",
      "status.local": "Tudo é calculado localmente; nenhuma base real é consultada.",
      "aurora.shell.rail": "Principal",
      "aurora.shell.here": "Você está aqui",
      "aurora.shell.search": "Buscar…",
      "aurora.shell.skip": "Pular para o conteúdo",
      "aurora.shell.theme": "Tema",
      "aurora.cmdk.placeholder": "Digite um comando ou busque…",
      "aurora.cmdk.label": "Paleta de comandos",
      "aurora.cmdk.empty": "Nenhum comando encontrado",
      "aurora.table.search": "Buscar…",
      "aurora.table.searchLabel": "Buscar na tabela",
      "aurora.table.noMatches": "Nada encontrado",
      "aurora.table.nothing": "Nada para mostrar",
      "aurora.table.tryAnother": "Tente outro termo de busca.",
      "aurora.table.prev": "Anterior",
      "aurora.table.next": "Próxima",
      "aurora.table.of": "de",
      "aurora.theme.toLight": "Mudar para o tema claro",
      "aurora.theme.toDark": "Mudar para o tema escuro",
      "aurora.copy.failed": "Não foi possível copiar",
      "aurora.empty.title": "Nada aqui ainda",
      "tab.cpf": "CPF",
      "tab.cnpj": "CNPJ",
      "tab.pix": "PIX",
      "tab.card": "Cartão",
      "tab.plate": "Placa",
      "tab.phone": "Telefone",
      "tab.cep": "CEP",
      "tab.fake": "Pessoa fake",
      "algo.cpf": "Módulo 11",
      "algo.cnpj": "Módulo 11 · A–Z",
      "algo.pix": "CRC-16/CCITT-FALSE",
      "algo.card": "Luhn",
      "algo.plate": "Antiga → Mercosul",
      "algo.phone": "Plano de numeração",
      "algo.cep": "Faixas por UF",
      "algo.fake": "Semente reproduzível",
      "doc.name.cpf": "CPF",
      "doc.name.cnpj": "CNPJ",
      "doc.name.card": "cartão",
      "doc.name.plate": "placa",
      "doc.name.phone": "telefone",
      "doc.name.cep": "CEP",
      "doc.label.cpf": "CPF",
      "doc.label.cnpj": "CNPJ",
      "doc.label.card": "Número do cartão",
      "doc.label.plate": "Placa",
      "doc.label.phone": "Telefone",
      "doc.label.cep": "CEP",
      "doc.hint.cpf": "11 dígitos; os dois últimos são verificadores (módulo 11).",
      "doc.hint.cnpj": "14 caracteres; desde julho de 2026 as letras A–Z valem nos 12 primeiros.",
      "doc.hint.card": "Bandeira e verificação de Luhn. Use só números de teste.",
      "doc.hint.plate": "Formato antigo (AAA-9999) ou Mercosul (AAA9A99).",
      "doc.hint.phone": "Celular ou fixo do Brasil, com DDD; aceita +55 e pontuação.",
      "doc.hint.cep": "Oito dígitos. Só o formato é verificado, sem consulta de endereço.",
      "result.title": "Resultado",
      "validate.example.valid": "Exemplo válido",
      "validate.example.invalid": "Exemplo inválido",
      "validate.clear": "Limpar",
      "verdict.empty.title": "Aguardando um valor",
      "verdict.empty.text": "Digite ou cole um valor, ou use um exemplo.",
      "verdict.valid": "{doc} válido",
      "verdict.invalid": "{doc} inválido",
      "verdict.valid.f": "{doc} válida",
      "verdict.invalid.f": "{doc} inválida",
      "verdict.incomplete": "{doc} incompleto",
      "verdict.incomplete.f": "{doc} incompleta",
      "verdict.incomplete.text": "Foram informados {got} caracteres; continue digitando.",
      "verdict.checking": "Verificando…",
      "verdict.ok.cpf": "Os dois dígitos verificadores conferem.",
      "verdict.ok.cnpj": "Os dois dígitos verificadores conferem.",
      "verdict.ok.card": "Passa na verificação de Luhn.",
      "verdict.ok.plate": "O formato é reconhecido.",
      "verdict.ok.phone": "Número brasileiro com DDD existente.",
      "verdict.ok.cep": "O formato é válido; o CEP não é consultado.",
      "fact.normalized": "Normalizado",
      "fact.formatted": "Formatado",
      "fact.region": "Região fiscal",
      "fact.root": "Raiz",
      "fact.branch": "Filial",
      "fact.checkdigits": "Dígitos verificadores",
      "fact.kind": "Tipo",
      "fact.kind.numeric": "Numérico",
      "fact.kind.alnum": "Alfanumérico",
      "fact.hq": "Matriz",
      "fact.yes": "Sim",
      "fact.no": "Não",
      "fact.brand": "Bandeira",
      "fact.bin": "BIN",
      "fact.last4": "Final",
      "fact.length": "Tamanho",
      "fact.length.value": "{n} dígitos",
      "fact.cvv": "CVV",
      "fact.test": "Número de teste conhecido",
      "fact.layout": "Layout",
      "fact.layout.legacy": "Antigo (AAA-9999)",
      "fact.layout.mercosul": "Mercosul (AAA9A99)",
      "fact.mercosul": "Equivalente Mercosul",
      "fact.intl": "Internacional",
      "fact.area": "DDD",
      "fact.type": "Tipo",
      "fact.type.mobile": "Celular",
      "fact.type.landline": "Fixo",
      "fact.postal": "Região postal",
      "gen.title": "Gerar {doc}",
      "gen.sub": "Valores válidos e reproduzíveis: a mesma semente gera os mesmos valores.",
      "gen.button": "Gerar",
      "gen.count": "Quantidade",
      "gen.seed": "Semente (opcional)",
      "gen.seed.hint": "aleatória",
      "gen.formatted": "Com máscara",
      "gen.uf": "UF",
      "gen.any": "Qualquer",
      "gen.ddd": "DDD",
      "gen.alnum": "Alfanumérico",
      "gen.branch": "Filial",
      "gen.brand": "Bandeira",
      "gen.layout": "Layout",
      "gen.layout.mercosul": "Mercosul",
      "gen.layout.legacy": "Antigo",
      "gen.type": "Tipo",
      "gen.type.mobile": "Celular",
      "gen.type.landline": "Fixo",
      "gen.empty": "Nada gerado ainda.",
      "gen.seedused": "Semente usada: {seed}. Envie-a de volta para repetir o resultado.",
      "gen.validate": "Validar",
      "gen.copy": "Copiar",
      "gen.copyall": "Copiar todos",
      "gen.warn.card": "Números aleatórios de teste: nunca use em pagamentos reais.",
      "gen.warn.phone": "Podem pertencer a assinantes reais: não ligue para eles.",
      "explain.title": "Como funciona",
      "explain.sub.mod11": "Soma ponderada e resto da divisão por 11.",
      "explain.sub.luhn": "Algoritmo de Luhn, da direita para a esquerda.",
      "explain.sub.plate": "Como a placa antiga vira Mercosul.",
      "explain.sub.phone": "As regras do plano de numeração, uma a uma.",
      "explain.sub.cep": "Cada parte do CEP e o que ela diz.",
      "explain.sub.crc": "CRC16/CCITT-FALSE sobre o código, byte a byte.",
      "explain.empty.title": "Nada para explicar ainda",
      "explain.empty.text": "Informe um valor completo e válido o bastante para o cálculo aparecer aqui.",
      "ctrl.group": "Controles da animação",
      "ctrl.play": "Reproduzir",
      "ctrl.pause": "Pausar",
      "ctrl.restart": "Reiniciar",
      "ctrl.prev": "Passo anterior",
      "ctrl.next": "Próximo passo",
      "ctrl.skip": "+10 passos",
      "ctrl.end": "Ir ao fim",
      "ctrl.speed": "Velocidade",
      "ctrl.speed.slow": "Lenta",
      "ctrl.speed.normal": "Normal",
      "ctrl.speed.fast": "Rápida",
      "ctrl.progress": "Passo {n} de {total}",
      "row.char": "Caractere",
      "row.digit": "Dígito",
      "row.value": "Valor",
      "row.weight": "Peso",
      "row.product": "Produto",
      "row.running": "Soma parcial",
      "row.double": "Dobrar?",
      "row.counts": "Conta",
      "block.first": "1º dígito verificador",
      "block.second": "2º dígito verificador",
      "block.only": "Dígito verificador",
      "block.luhn": "Soma de Luhn",
      "eq.sum": "Soma {sum}",
      "eq.mod": "{sum} mod {modulus} = {remainder}",
      "eq.digit": "dígito {digit}",
      "eq.match": "Confere",
      "eq.nomatch": "Não confere",
      "eq.valid": "Válido",
      "eq.invalid": "Inválido",
      "cap.start.mod11": "Cada caractere é multiplicado pelo seu peso; depois somamos tudo.",
      "cap.mult": "{char} × {weight} = {product}",
      "cap.mult.alnum": "{char} vale {value} (código ASCII {code} − 48): {value} × {weight} = {product}",
      "cap.sum": "Soma dos produtos: {sum}.",
      "cap.mod": "{sum} dividido por {modulus} deixa resto {remainder}.",
      "cap.digit.zero": "Resto {remainder} é menor que 2: o dígito é 0.",
      "cap.digit.sub": "{modulus} − {remainder} = {digit}: o dígito é {digit}.",
      "cap.verdict.ok": "O documento traz {actual}: confere.",
      "cap.verdict.bad": "O documento traz {actual}, mas o correto é {digit}: não confere.",
      "cap.note.alnum": "Letras valem o código ASCII menos 48: A = 17, B = 18, … Z = 42.",
      "cap.start.luhn": "Da direita para a esquerda, dobra-se um dígito sim, outro não; depois somam-se os resultados.",
      "cap.luhn.keep": "{digit} entra como está.",
      "cap.luhn.double": "{digit} × 2 = {doubled}.",
      "cap.luhn.double.big": "{digit} × 2 = {doubled}; passa de 9, então subtrai-se 9: {value}.",
      "cap.luhn.sum": "Soma: {sum}.",
      "cap.luhn.mod": "{sum} dividido por 10 deixa resto {remainder}.",
      "cap.luhn.ok": "Resto 0: o número é válido.",
      "cap.luhn.bad": "Resto {remainder}: precisava ser 0, então o número é inválido.",
      "cap.plate.0": "Placa antiga: três letras e quatro números (AAA-9999).",
      "cap.plate.1": "A Mercosul usa AAA9A99: o 5º caractere deixa de ser número e passa a ser letra.",
      "cap.plate.2": "Tabela de conversão: 0→A, 1→B, 2→C … 9→J. Aqui o {digit} vira {letter}.",
      "cap.plate.3": "Resultado: {plate}.",
      "cap.plate.m0": "Placa Mercosul: três letras, um número, uma letra e dois números (AAA9A99).",
      "cap.plate.m1": "Placas antigas viram Mercosul trocando o 5º caractere: o número vira letra (0→A … 9→J).",
      "cap.phone.0": "Primeiro, só os dígitos importam: {digits}.",
      "cap.phone.1": "O DDD {area} existe e pertence a {uf}.",
      "cap.phone.mobile": "Celular: 9 dígitos começando com 9 ({number}).",
      "cap.phone.landline": "Fixo: 8 dígitos começando com 2, 3, 4 ou 5 ({number}).",
      "cap.phone.2": "Forma internacional (E.164): {e164}.",
      "cap.cep.0": "Um CEP tem 8 dígitos: cinco de prefixo e três de sufixo (NNNNN-NNN).",
      "cap.cep.1": "O primeiro dígito ({digit}) indica a região postal: {regions}.",
      "cap.cep.2": "O prefixo {prefix} cai na faixa de {uf}.",
      "cap.cep.3": "Só o formato é verificado: não há consulta de endereço.",
      "tok.country": "país",
      "tok.area": "DDD",
      "tok.number": "número",
      "tok.region": "região",
      "tok.prefix": "prefixo",
      "tok.suffix": "sufixo",
      "cep.region.0": "Grande São Paulo",
      "cep.region.1": "interior e litoral de SP",
      "cep.region.2": "RJ e ES",
      "cep.region.3": "MG",
      "cep.region.4": "BA e SE",
      "cep.region.5": "PE, AL, PB e RN",
      "cep.region.6": "CE, PI, MA, PA, AM, AC, AP e RR",
      "cep.region.7": "DF, GO, TO, MT, MS e RO",
      "cep.region.8": "PR e SC",
      "cep.region.9": "RS",
      "pix.build.title": "Montar BR Code",
      "pix.build.sub": "Gera o código copia e cola de um PIX estático.",
      "pix.field.key": "Chave PIX",
      "pix.ph.key": "CPF, CNPJ, +55…, e-mail ou chave aleatória",
      "pix.field.keytype": "Tipo da chave",
      "pix.keytype.auto": "Detectar",
      "pix.keytype.cpf": "CPF",
      "pix.keytype.cnpj": "CNPJ",
      "pix.keytype.phone": "Telefone",
      "pix.keytype.email": "E-mail",
      "pix.keytype.evp": "Chave aleatória",
      "pix.field.name": "Nome do recebedor",
      "pix.field.city": "Cidade",
      "pix.field.amount": "Valor (opcional)",
      "pix.field.txid": "Identificador, txid (opcional)",
      "pix.field.message": "Mensagem (opcional)",
      "pix.built": "Copia e cola",
      "pix.copy": "Copiar código",
      "pix.todecoder": "Decodificar este código",
      "pix.crc": "CRC {crc}",
      "pix.keytype.detected": "tipo: {type}",
      "pix.build.error": "Não foi possível montar o código: corrija os campos indicados.",
      "pix.decode.sub": "Lê a estrutura TLV e confere os campos e o CRC.",
      "pix.decode.field": "Código PIX (copia e cola)",
      "pix.decode.example": "Exemplo do Banco Central",
      "pix.decode.tamper": "Alterar 1 caractere",
      "pix.decode.valid": "BR Code válido",
      "pix.decode.invalid": "BR Code inválido",
      "pix.decode.empty": "Cole um código PIX para decodificar.",
      "pix.decode.crc.ok": "O CRC {crc} confere com o conteúdo.",
      "pix.facts.key": "Chave",
      "pix.facts.keytype": "Tipo da chave",
      "pix.facts.merchant": "Recebedor",
      "pix.facts.city": "Cidade",
      "pix.facts.amount": "Valor",
      "pix.facts.open": "Em aberto (o pagador digita)",
      "pix.facts.txid": "txid",
      "pix.facts.message": "Mensagem",
      "pix.tree.title": "Estrutura TLV",
      "pix.tree.len": "{n} car.",
      "tlv.root.00": "Indicador de formato",
      "tlv.root.01": "Método de iniciação",
      "tlv.root.52": "Categoria do estabelecimento (MCC)",
      "tlv.root.53": "Moeda (986 = real)",
      "tlv.root.54": "Valor",
      "tlv.root.58": "País",
      "tlv.root.59": "Nome do recebedor",
      "tlv.root.60": "Cidade do recebedor",
      "tlv.root.62": "Dados adicionais",
      "tlv.root.63": "CRC16",
      "tlv.merchant": "Conta do recebedor",
      "tlv.m.00": "Identificador do arranjo (GUI)",
      "tlv.m.01": "Chave PIX",
      "tlv.m.02": "Informação adicional",
      "tlv.m.25": "URL do payload",
      "tlv.a.05": "Identificador (txid)",
      "crc.title": "CRC16 passo a passo",
      "crc.intro": "Cada byte do código passa por um registrador de 16 bits que começa em FFFF. No fim, o registrador é o CRC.",
      "crc.byte": "Byte",
      "crc.before": "Registrador antes",
      "crc.final": "Registrador final {crc}",
      "crc.carried": "CRC do código {crc}",
      "crc.index": "Índice = (reg >> 8) XOR byte",
      "crc.table": "Tabela[índice]",
      "crc.reg": "Novo reg = (reg << 8) XOR tabela",
      "crc.cap.step": "Byte {n} de {total}: {char} (0x{hex}).",
      "crc.cap.end.ok": "O registrador terminou em {crc}, igual ao CRC do código: confere.",
      "crc.cap.end.bad": "O registrador terminou em {expected}, mas o código traz {actual}: não confere.",
      "crc.all": "Todos os passos",
      "crc.col.n": "Nº",
      "crc.empty": "Decodifique um código PIX com CRC para ver o cálculo.",
      "fake.title": "Pessoas fictícias",
      "fake.sub": "Geradas por algoritmo a partir de uma semente.",
      "fake.notice.title": "Dados fictícios",
      "fake.notice.text": "Estas pessoas não existem. O CPF passa na verificação, mas não pertence a ninguém; os e-mails usam domínios reservados (example.org).",
      "fake.gender.M": "Masculino",
      "fake.gender.F": "Feminino",
      "fake.cpf": "CPF",
      "fake.phone": "Telefone",
      "fake.email": "E-mail",
      "fake.born": "Nascimento",
      "fake.address": "Endereço",
      "fake.explain": "Explicar CPF",
      "fake.json": "Copiar JSON",
      "fake.selected": "CPF de {name}",
      "fake.region": "O 9º dígito do CPF ({digit}) corresponde a {ufs}; o endereço desta pessoa é em {uf}.",
      "fake.empty": "Gere pessoas para ver os dados.",
      "copied": "Copiado",
      "err.rate": "Muitas requisições. Tente de novo em {seconds} s.",
      "err.offline": "Não foi possível falar com a API. Inicie o servidor com: brkit serve",
      "err.generic": "A API respondeu com erro ({status}). Id da requisição: {id}",
      "err.invalid": "Valor recusado pela API: {message}",
      "issue.blank": "O valor está vazio.",
      "issue.too_long": "O valor é longo demais.",
      "issue.invalid_characters": "Há caracteres não permitidos: {found}.",
      "issue.invalid_length": "Quantidade errada de caracteres: foram informados {got}.",
      "issue.repeated_digits": "Todos os dígitos são iguais, o que nunca é válido.",
      "issue.checksum": "O {which} não confere (esperado {expected}, informado {got}).",
      "issue.which.first": "primeiro dígito verificador",
      "issue.which.second": "segundo dígito verificador",
      "issue.which.only": "dígito verificador",
      "issue.invalid_check_digits": "Os dois últimos caracteres (dígitos verificadores) devem ser números.",
      "issue.luhn": "Falha na verificação de Luhn.",
      "issue.brand_length": "Números {brand} têm {lengths} dígitos; foram informados {got}.",
      "issue.foreign_number": "Só números brasileiros (+55) são aceitos.",
      "issue.invalid_area_code": "{area} não é um DDD atribuído pela Anatel.",
      "issue.legacy_mobile": "Números de 8 dígitos começando com 6 a 9 eram celulares antes do nono dígito; hoje celulares têm 9 dígitos começando com 9.",
      "issue.invalid_mobile": "Números de 9 dígitos (celular) devem começar com 9.",
      "issue.invalid_landline": "Números de 8 dígitos (fixo) devem começar com 2, 3, 4 ou 5.",
      "issue.unassigned_prefix": "CEPs começam em 01000-000; prefixos menores não são atribuídos.",
      "issue.invalid_format": "Esperado AAA-9999 (antigo) ou AAA9A99 (Mercosul).",
      "issue.crc_mismatch": "O CRC do código ({actual}) é diferente do calculado ({expected}).",
      "issue.bad_format_indicator": "O código deve começar com 000201.",
      "issue.missing_crc": "O código deve terminar com o campo CRC (6304 e 4 dígitos hexadecimais).",
      "issue.duplicate_field": "O campo {field} aparece mais de uma vez.",
      "issue.missing_field": "O campo {field} é obrigatório.",
      "issue.unexpected_value": "Valor inesperado no campo {field}.",
      "issue.field_length": "Tamanho inválido no campo {field}.",
      "issue.invalid_amount": "O valor deve ser um número decimal positivo, como 12.50.",
      "issue.missing_pix_key": "O modelo PIX precisa de uma chave (01) ou de uma URL (25).",
      "issue.malformed_tlv": "Estrutura TLV inválida: {message}",
      "issue.control_characters": "O código deve ser uma única linha, sem caracteres de controle.",
      "issue.invalid_integer": "O valor de {field} deve ser um número inteiro.",
      "issue.out_of_range": "O valor de {field} está fora do intervalo permitido.",
      "issue.not_allowed": "Valor não permitido para {field}.",
      "issue.missing": "O campo {field} é obrigatório.",
      "issue.invalid_txid": "O txid deve ter de 1 a 25 letras ou números.",
      "issue.amount_too_large": "O valor tem dígitos demais.",
      "issue.template_too_long": "A chave e a mensagem juntas passam do limite de 99 caracteres.",
      "issue.unrecognised_key": "Não foi possível identificar o tipo da chave: use CPF, CNPJ, celular com +55, e-mail ou chave aleatória (UUID).",
      "cmd.group.nav": "Ir para",
      "cmd.group.actions": "Ações",
      "cmd.group.prefs": "Preferências",
      "cmd.goto": "Ir para {tab}",
      "cmd.generate": "Gerar valores nesta aba",
      "cmd.replay": "Reproduzir a animação",
      "cmd.example": "Usar o exemplo válido",
      "cmd.theme": "Alternar tema claro ou escuro",
      "cmd.lang": "Mudar o idioma para {lang}",
      "cmd.lang.target": "English",
      "cmd.openapi": "Abrir a descrição OpenAPI"
    },
    "en": {
      "app.title": "Kit Brasil · brkit",
      "app.eyebrow": "Interactive playground",
      "app.lead": "Validate, generate and understand Brazilian documents. Every check digit is computed in front of you, step by step.",
      "app.chip.api": "Real API at /api/v1",
      "app.chip.offline": "Works offline",
      "app.chip.deps": "No dependencies",
      "live.connecting": "Connecting…",
      "live.ok": "API v{version}",
      "live.offline": "API unavailable",
      "top.lang": "Language",
      "tabs.label": "Tools",
      "rail.playground": "Playground",
      "rail.api": "API (OpenAPI)",
      "rail.palette": "Command palette",
      "status.version": "brkit {version}",
      "status.license": "MIT licence",
      "status.local": "Everything is computed locally; no real database is queried.",
      "aurora.shell.rail": "Primary",
      "aurora.shell.here": "You are here",
      "aurora.shell.search": "Search…",
      "aurora.shell.skip": "Skip to content",
      "aurora.shell.theme": "Theme",
      "aurora.cmdk.placeholder": "Type a command or search…",
      "aurora.cmdk.label": "Command palette",
      "aurora.cmdk.empty": "No matching commands",
      "aurora.table.search": "Search…",
      "aurora.table.searchLabel": "Search table",
      "aurora.table.noMatches": "No matches",
      "aurora.table.nothing": "Nothing to show",
      "aurora.table.tryAnother": "Try a different search term.",
      "aurora.table.prev": "Previous",
      "aurora.table.next": "Next",
      "aurora.table.of": "of",
      "aurora.theme.toLight": "Switch to light theme",
      "aurora.theme.toDark": "Switch to dark theme",
      "aurora.copy.failed": "Copy failed",
      "aurora.empty.title": "Nothing here yet",
      "tab.cpf": "CPF",
      "tab.cnpj": "CNPJ",
      "tab.pix": "PIX",
      "tab.card": "Card",
      "tab.plate": "Plate",
      "tab.phone": "Phone",
      "tab.cep": "CEP",
      "tab.fake": "Fake person",
      "algo.cpf": "Modulo 11",
      "algo.cnpj": "Modulo 11 · A–Z",
      "algo.pix": "CRC-16/CCITT-FALSE",
      "algo.card": "Luhn",
      "algo.plate": "Legacy → Mercosul",
      "algo.phone": "Numbering plan",
      "algo.cep": "State ranges",
      "algo.fake": "Seeded, reproducible",
      "doc.name.cpf": "CPF",
      "doc.name.cnpj": "CNPJ",
      "doc.name.card": "card",
      "doc.name.plate": "plate",
      "doc.name.phone": "phone number",
      "doc.name.cep": "CEP",
      "doc.label.cpf": "CPF",
      "doc.label.cnpj": "CNPJ",
      "doc.label.card": "Card number",
      "doc.label.plate": "Plate",
      "doc.label.phone": "Phone number",
      "doc.label.cep": "CEP",
      "doc.hint.cpf": "11 digits; the last two are check digits (modulo 11).",
      "doc.hint.cnpj": "14 characters; since July 2026 the letters A–Z are allowed in the first 12.",
      "doc.hint.card": "Brand and Luhn check. Use test numbers only.",
      "doc.hint.plate": "Legacy (AAA-9999) or Mercosul (AAA9A99) layout.",
      "doc.hint.phone": "Brazilian mobile or landline with area code; accepts +55 and punctuation.",
      "doc.hint.cep": "Eight digits. Only the shape is checked; there is no address lookup.",
      "result.title": "Result",
      "validate.example.valid": "Valid example",
      "validate.example.invalid": "Invalid example",
      "validate.clear": "Clear",
      "verdict.empty.title": "Waiting for a value",
      "verdict.empty.text": "Type or paste a value, or use an example.",
      "verdict.valid": "Valid {doc}",
      "verdict.invalid": "Invalid {doc}",
      "verdict.valid.f": "Valid {doc}",
      "verdict.invalid.f": "Invalid {doc}",
      "verdict.incomplete": "Incomplete {doc}",
      "verdict.incomplete.f": "Incomplete {doc}",
      "verdict.incomplete.text": "{got} characters so far; keep typing.",
      "verdict.checking": "Checking…",
      "verdict.ok.cpf": "Both check digits match.",
      "verdict.ok.cnpj": "Both check digits match.",
      "verdict.ok.card": "Passes the Luhn check.",
      "verdict.ok.plate": "The layout is recognised.",
      "verdict.ok.phone": "Brazilian number with an existing area code.",
      "verdict.ok.cep": "The shape is valid; the CEP is not looked up.",
      "fact.normalized": "Normalised",
      "fact.formatted": "Formatted",
      "fact.region": "Fiscal region",
      "fact.root": "Root",
      "fact.branch": "Branch",
      "fact.checkdigits": "Check digits",
      "fact.kind": "Kind",
      "fact.kind.numeric": "Numeric",
      "fact.kind.alnum": "Alphanumeric",
      "fact.hq": "Head office",
      "fact.yes": "Yes",
      "fact.no": "No",
      "fact.brand": "Brand",
      "fact.bin": "BIN",
      "fact.last4": "Last 4",
      "fact.length": "Length",
      "fact.length.value": "{n} digits",
      "fact.cvv": "CVV",
      "fact.test": "Known test number",
      "fact.layout": "Layout",
      "fact.layout.legacy": "Legacy (AAA-9999)",
      "fact.layout.mercosul": "Mercosul (AAA9A99)",
      "fact.mercosul": "Mercosul equivalent",
      "fact.intl": "International",
      "fact.area": "Area code",
      "fact.type": "Type",
      "fact.type.mobile": "Mobile",
      "fact.type.landline": "Landline",
      "fact.postal": "Postal region",
      "gen.title": "Generate {doc}",
      "gen.sub": "Valid, reproducible values: the same seed gives the same values.",
      "gen.button": "Generate",
      "gen.count": "Count",
      "gen.seed": "Seed (optional)",
      "gen.seed.hint": "random",
      "gen.formatted": "Formatted",
      "gen.uf": "State",
      "gen.any": "Any",
      "gen.ddd": "Area code",
      "gen.alnum": "Alphanumeric",
      "gen.branch": "Branch",
      "gen.brand": "Brand",
      "gen.layout": "Layout",
      "gen.layout.mercosul": "Mercosul",
      "gen.layout.legacy": "Legacy",
      "gen.type": "Type",
      "gen.type.mobile": "Mobile",
      "gen.type.landline": "Landline",
      "gen.empty": "Nothing generated yet.",
      "gen.seedused": "Seed used: {seed}. Send it back to repeat the result.",
      "gen.validate": "Validate",
      "gen.copy": "Copy",
      "gen.copyall": "Copy all",
      "gen.warn.card": "Random test numbers: never use them for real payments.",
      "gen.warn.phone": "They may belong to real subscribers: do not call them.",
      "explain.title": "How it works",
      "explain.sub.mod11": "Weighted sum and the remainder of the division by 11.",
      "explain.sub.luhn": "The Luhn algorithm, right to left.",
      "explain.sub.plate": "How a legacy plate becomes Mercosul.",
      "explain.sub.phone": "The numbering-plan rules, one by one.",
      "explain.sub.cep": "Each part of a CEP and what it tells.",
      "explain.sub.crc": "CRC16/CCITT-FALSE over the payload, byte by byte.",
      "explain.empty.title": "Nothing to explain yet",
      "explain.empty.text": "Enter a value that is complete enough for the computation to appear here.",
      "ctrl.group": "Animation controls",
      "ctrl.play": "Play",
      "ctrl.pause": "Pause",
      "ctrl.restart": "Restart",
      "ctrl.prev": "Previous step",
      "ctrl.next": "Next step",
      "ctrl.skip": "+10 steps",
      "ctrl.end": "Skip to end",
      "ctrl.speed": "Speed",
      "ctrl.speed.slow": "Slow",
      "ctrl.speed.normal": "Normal",
      "ctrl.speed.fast": "Fast",
      "ctrl.progress": "Step {n} of {total}",
      "row.char": "Character",
      "row.digit": "Digit",
      "row.value": "Value",
      "row.weight": "Weight",
      "row.product": "Product",
      "row.running": "Running sum",
      "row.double": "Double?",
      "row.counts": "Counts",
      "block.first": "First check digit",
      "block.second": "Second check digit",
      "block.only": "Check digit",
      "block.luhn": "Luhn sum",
      "eq.sum": "Sum {sum}",
      "eq.mod": "{sum} mod {modulus} = {remainder}",
      "eq.digit": "digit {digit}",
      "eq.match": "Matches",
      "eq.nomatch": "Does not match",
      "eq.valid": "Valid",
      "eq.invalid": "Invalid",
      "cap.start.mod11": "Each character is multiplied by its weight; then everything is added up.",
      "cap.mult": "{char} × {weight} = {product}",
      "cap.mult.alnum": "{char} is worth {value} (ASCII code {code} − 48): {value} × {weight} = {product}",
      "cap.sum": "Sum of the products: {sum}.",
      "cap.mod": "{sum} divided by {modulus} leaves remainder {remainder}.",
      "cap.digit.zero": "Remainder {remainder} is below 2: the digit is 0.",
      "cap.digit.sub": "{modulus} − {remainder} = {digit}: the digit is {digit}.",
      "cap.verdict.ok": "The document has {actual}: it matches.",
      "cap.verdict.bad": "The document has {actual} but it should be {digit}: no match.",
      "cap.note.alnum": "Letters are worth their ASCII code minus 48: A = 17, B = 18, … Z = 42.",
      "cap.start.luhn": "From the right, every second digit is doubled; then the results are added up.",
      "cap.luhn.keep": "{digit} counts as it is.",
      "cap.luhn.double": "{digit} × 2 = {doubled}.",
      "cap.luhn.double.big": "{digit} × 2 = {doubled}; above 9, so subtract 9: {value}.",
      "cap.luhn.sum": "Sum: {sum}.",
      "cap.luhn.mod": "{sum} divided by 10 leaves remainder {remainder}.",
      "cap.luhn.ok": "Remainder 0: the number is valid.",
      "cap.luhn.bad": "Remainder {remainder}: it had to be 0, so the number is invalid.",
      "cap.plate.0": "Legacy plate: three letters and four digits (AAA-9999).",
      "cap.plate.1": "Mercosul uses AAA9A99: the 5th character stops being a digit and becomes a letter.",
      "cap.plate.2": "Conversion table: 0→A, 1→B, 2→C … 9→J. Here {digit} becomes {letter}.",
      "cap.plate.3": "Result: {plate}.",
      "cap.plate.m0": "Mercosul plate: three letters, a digit, a letter and two digits (AAA9A99).",
      "cap.plate.m1": "Legacy plates become Mercosul by replacing the 5th character: the digit turns into a letter (0→A … 9→J).",
      "cap.phone.0": "First, only the digits matter: {digits}.",
      "cap.phone.1": "Area code {area} exists and belongs to {uf}.",
      "cap.phone.mobile": "Mobile: 9 digits starting with 9 ({number}).",
      "cap.phone.landline": "Landline: 8 digits starting with 2, 3, 4 or 5 ({number}).",
      "cap.phone.2": "International form (E.164): {e164}.",
      "cap.cep.0": "A CEP has 8 digits: five of prefix and three of suffix (NNNNN-NNN).",
      "cap.cep.1": "The first digit ({digit}) is the postal region: {regions}.",
      "cap.cep.2": "Prefix {prefix} falls in the range of {uf}.",
      "cap.cep.3": "Only the shape is checked: there is no address lookup.",
      "tok.country": "country",
      "tok.area": "area code",
      "tok.number": "number",
      "tok.region": "region",
      "tok.prefix": "prefix",
      "tok.suffix": "suffix",
      "cep.region.0": "Greater São Paulo",
      "cep.region.1": "inland and coastal SP",
      "cep.region.2": "RJ and ES",
      "cep.region.3": "MG",
      "cep.region.4": "BA and SE",
      "cep.region.5": "PE, AL, PB and RN",
      "cep.region.6": "CE, PI, MA, PA, AM, AC, AP and RR",
      "cep.region.7": "DF, GO, TO, MT, MS and RO",
      "cep.region.8": "PR and SC",
      "cep.region.9": "RS",
      "pix.build.title": "Build a BR Code",
      "pix.build.sub": "Builds the copy-and-paste code of a static PIX.",
      "pix.field.key": "PIX key",
      "pix.ph.key": "CPF, CNPJ, +55…, e-mail or random key",
      "pix.field.keytype": "Key type",
      "pix.keytype.auto": "Detect",
      "pix.keytype.cpf": "CPF",
      "pix.keytype.cnpj": "CNPJ",
      "pix.keytype.phone": "Phone",
      "pix.keytype.email": "E-mail",
      "pix.keytype.evp": "Random key",
      "pix.field.name": "Merchant name",
      "pix.field.city": "City",
      "pix.field.amount": "Amount (optional)",
      "pix.field.txid": "Reference id, txid (optional)",
      "pix.field.message": "Message (optional)",
      "pix.built": "Copy and paste",
      "pix.copy": "Copy code",
      "pix.todecoder": "Decode this code",
      "pix.crc": "CRC {crc}",
      "pix.keytype.detected": "type: {type}",
      "pix.build.error": "Could not build the code: fix the fields marked below.",
      "pix.decode.sub": "Reads the TLV structure and checks the fields and the CRC.",
      "pix.decode.field": "PIX code (copy and paste)",
      "pix.decode.example": "Banco Central example",
      "pix.decode.tamper": "Change 1 character",
      "pix.decode.valid": "Valid BR Code",
      "pix.decode.invalid": "Invalid BR Code",
      "pix.decode.empty": "Paste a PIX code to decode it.",
      "pix.decode.crc.ok": "The CRC {crc} matches the content.",
      "pix.facts.key": "Key",
      "pix.facts.keytype": "Key type",
      "pix.facts.merchant": "Merchant",
      "pix.facts.city": "City",
      "pix.facts.amount": "Amount",
      "pix.facts.open": "Open (the payer types it)",
      "pix.facts.txid": "txid",
      "pix.facts.message": "Message",
      "pix.tree.title": "TLV structure",
      "pix.tree.len": "{n} chars",
      "tlv.root.00": "Payload format indicator",
      "tlv.root.01": "Point of initiation method",
      "tlv.root.52": "Merchant category code (MCC)",
      "tlv.root.53": "Currency (986 = real)",
      "tlv.root.54": "Amount",
      "tlv.root.58": "Country",
      "tlv.root.59": "Merchant name",
      "tlv.root.60": "Merchant city",
      "tlv.root.62": "Additional data",
      "tlv.root.63": "CRC16",
      "tlv.merchant": "Merchant account",
      "tlv.m.00": "Scheme identifier (GUI)",
      "tlv.m.01": "PIX key",
      "tlv.m.02": "Additional information",
      "tlv.m.25": "Payload URL",
      "tlv.a.05": "Reference label (txid)",
      "crc.title": "CRC16 step by step",
      "crc.intro": "Every byte of the code goes through a 16-bit register that starts at FFFF. At the end the register is the CRC.",
      "crc.byte": "Byte",
      "crc.before": "Register before",
      "crc.final": "Final register {crc}",
      "crc.carried": "Code CRC {crc}",
      "crc.index": "Index = (reg >> 8) XOR byte",
      "crc.table": "Table[index]",
      "crc.reg": "New reg = (reg << 8) XOR table",
      "crc.cap.step": "Byte {n} of {total}: {char} (0x{hex}).",
      "crc.cap.end.ok": "The register ended at {crc}, equal to the code's CRC: it matches.",
      "crc.cap.end.bad": "The register ended at {expected} but the code carries {actual}: no match.",
      "crc.all": "All steps",
      "crc.col.n": "No.",
      "crc.empty": "Decode a PIX code with a CRC to see the computation.",
      "fake.title": "Fictitious people",
      "fake.sub": "Generated by an algorithm from a seed.",
      "fake.notice.title": "Fictitious data",
      "fake.notice.text": "These people do not exist. The CPF passes the check but belongs to nobody; e-mail addresses use reserved domains (example.org).",
      "fake.gender.M": "Male",
      "fake.gender.F": "Female",
      "fake.cpf": "CPF",
      "fake.phone": "Phone",
      "fake.email": "E-mail",
      "fake.born": "Born",
      "fake.address": "Address",
      "fake.explain": "Explain CPF",
      "fake.json": "Copy JSON",
      "fake.selected": "{name}'s CPF",
      "fake.region": "The CPF's 9th digit ({digit}) corresponds to {ufs}; this person's address is in {uf}.",
      "fake.empty": "Generate people to see the data.",
      "copied": "Copied",
      "err.rate": "Too many requests. Try again in {seconds} s.",
      "err.offline": "Could not reach the API. Start the server with: brkit serve",
      "err.generic": "The API answered with an error ({status}). Request id: {id}",
      "err.invalid": "Value refused by the API: {message}",
      "issue.blank": "The value is empty.",
      "issue.too_long": "The value is too long.",
      "issue.invalid_characters": "There are characters that are not allowed: {found}.",
      "issue.invalid_length": "Wrong number of characters: {got} given.",
      "issue.repeated_digits": "All the digits are the same, which is never valid.",
      "issue.checksum": "The {which} does not match (expected {expected}, got {got}).",
      "issue.which.first": "first check digit",
      "issue.which.second": "second check digit",
      "issue.which.only": "check digit",
      "issue.invalid_check_digits": "The last two characters (check digits) must be digits.",
      "issue.luhn": "The Luhn check fails.",
      "issue.brand_length": "{brand} numbers have {lengths} digits; {got} given.",
      "issue.foreign_number": "Only Brazilian numbers (+55) are accepted.",
      "issue.invalid_area_code": "{area} is not an area code assigned by Anatel.",
      "issue.legacy_mobile": "8-digit numbers starting with 6 to 9 were mobile numbers before the ninth digit; today mobile numbers have 9 digits starting with 9.",
      "issue.invalid_mobile": "9-digit (mobile) numbers must start with 9.",
      "issue.invalid_landline": "8-digit (landline) numbers must start with 2, 3, 4 or 5.",
      "issue.unassigned_prefix": "CEPs start at 01000-000; lower prefixes are not assigned.",
      "issue.invalid_format": "Expected AAA-9999 (legacy) or AAA9A99 (Mercosul).",
      "issue.crc_mismatch": "The code's CRC ({actual}) differs from the computed one ({expected}).",
      "issue.bad_format_indicator": "The code must start with 000201.",
      "issue.missing_crc": "The code must end with the CRC field (6304 and 4 hexadecimal digits).",
      "issue.duplicate_field": "Field {field} appears more than once.",
      "issue.missing_field": "Field {field} is required.",
      "issue.unexpected_value": "Unexpected value in field {field}.",
      "issue.field_length": "Invalid length in field {field}.",
      "issue.invalid_amount": "The amount must be a positive decimal number such as 12.50.",
      "issue.missing_pix_key": "The PIX template needs a key (01) or a URL (25).",
      "issue.malformed_tlv": "Malformed TLV structure: {message}",
      "issue.control_characters": "The code must be a single line without control characters.",
      "issue.invalid_integer": "The value of {field} must be a whole number.",
      "issue.out_of_range": "The value of {field} is outside the allowed range.",
      "issue.not_allowed": "That value is not allowed for {field}.",
      "issue.missing": "The field {field} is required.",
      "issue.invalid_txid": "The txid must have 1 to 25 letters or digits.",
      "issue.amount_too_large": "The amount has too many digits.",
      "issue.template_too_long": "The key and the message together exceed the 99-character limit.",
      "issue.unrecognised_key": "Could not tell the key type: use a CPF, a CNPJ, a mobile number with +55, an e-mail or a random key (UUID).",
      "cmd.group.nav": "Go to",
      "cmd.group.actions": "Actions",
      "cmd.group.prefs": "Preferences",
      "cmd.goto": "Go to {tab}",
      "cmd.generate": "Generate values on this tab",
      "cmd.replay": "Replay the animation",
      "cmd.example": "Use the valid example",
      "cmd.theme": "Toggle light or dark theme",
      "cmd.lang": "Switch the language to {lang}",
      "cmd.lang.target": "Português",
      "cmd.openapi": "Open the OpenAPI description"
    }
  } /* i18n:end */;

  /* ════════════════════════════ 2. helpers ════════════════════════════ */
  const LANG_KEY = 'brkit-lang';
  const lang = { current: 'pt' };
  try {
    const stored = window.localStorage.getItem(LANG_KEY);
    if (stored === 'en' || stored === 'pt') lang.current = stored;
  } catch (error) { /* storage unavailable: keep the default */ }

  function t(key, params) {
    let text = MESSAGES[lang.current][key];
    if (text === undefined) text = MESSAGES.pt[key];
    if (text === undefined) return key;
    if (!params) return text;
    return text.replace(/\{(\w+)\}/g, (whole, name) => (params[name] === undefined ? whole : String(params[name])));
  }
  const cap = (text) => text.charAt(0).toUpperCase() + text.slice(1);
  const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
  const hex = (value, width) => value.toString(16).toUpperCase().padStart(width || 2, '0');
  const printable = (byte) => (byte >= 32 && byte < 127 ? String.fromCharCode(byte) : '·');
  const mono = (text) => el('span', { class: 'a-mono a-num' }, text);
  const clear = (node) => { while (node.firstChild) node.removeChild(node.firstChild); return node; };
  const sleepless = () => Aurora.reducedMotion();

  /** A small round button with an icon only; the label is for assistive technology. */
  function iconButton(name, label, onClick, extra) {
    return el('button', { class: `a-btn a-btn--ghost a-btn--icon a-btn--sm ${extra || ''}`.trim(), type: 'button', 'aria-label': label, title: label, onclick: onClick }, icon(name, { size: 15 }));
  }

  /** Copies text and confirms with a toast in the current language. */
  function copyText(text) {
    return Aurora.copy(text, { label: t('copied') });
  }

  function copyButton(getText, label, tiny) {
    return iconButton('copy', label, () => copyText(typeof getText === 'function' ? getText() : getText), tiny ? 'pg-copy pg-copy--tiny' : 'pg-copy');
  }

  /** Translates the code of a validator or builder problem; the API's English text is the fallback. */
  function describeIssue(issue) {
    const key = `issue.${issue.code}`;
    if (MESSAGES.pt[key] === undefined) return issue.message;
    const message = issue.message || '';
    const pick = (pattern) => (message.match(pattern) || [])[1];
    const params = { field: issue.field, message };
    switch (issue.code) {
      case 'invalid_characters': params.found = pick(/\(found (.*)\)$/) || ''; break;
      case 'invalid_length': params.got = pick(/got (\d+)/) || '?'; break;
      case 'checksum': {
        const which = pick(/^(first|second) check digit/);
        const numbers = message.match(/expected (\d+), got (\d+)/) || [];
        params.which = t(`issue.which.${which || 'only'}`);
        params.expected = numbers[1];
        params.got = numbers[2];
        break;
      }
      case 'brand_length': {
        const parts = message.match(/^(.+?) numbers have ([\d, ]+) digits, got (\d+)/) || [];
        params.brand = parts[1]; params.lengths = parts[2]; params.got = parts[3];
        break;
      }
      case 'invalid_area_code': params.area = pick(/^(\d+) is not/); break;
      case 'crc_mismatch': {
        const parts = message.match(/carries (\w+) but its content hashes to (\w+)/) || [];
        params.actual = parts[1]; params.expected = parts[2];
        break;
      }
      case 'missing': params.field = fieldName(issue.field); break;
      default: break;
    }
    return t(key, params);
  }

  function fieldName(field) {
    const key = `pix.field.${field}`;
    if (MESSAGES.pt[key] === undefined) return field;
    return t(key).replace(/\s*\([^)]*\)\s*$/, '');
  }

  /* ════════════════════════════ 3. API client ════════════════════════════ */
  class ApiError extends Error {
    constructor(status, problem, retryAfter) {
      super((problem && problem.detail) || `HTTP ${status}`);
      this.status = status;
      this.problem = problem || null;
      this.retryAfter = retryAfter || 0;
    }
  }

  const liveState = { ui: null, version: '', state: 'connecting' };
  function setLive(state) {
    liveState.state = state;
    if (!liveState.ui) return;
    const label = { live: t('live.ok', { version: liveState.version }), connecting: t('live.connecting'), offline: t('live.offline') }[state];
    liveState.ui.set(state, label);
  }

  /** True when the first call of the page found no API: the tools show that at once instead of failing call by call. */
  const apiDown = () => liveState.state === 'offline';
  const unreachable = () => new ApiError(0, null, 0);

  function queryString(params) {
    const parts = [];
    Object.keys(params || {}).forEach((key) => {
      const value = params[key];
      if (value === undefined || value === null || value === '') return;
      parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
    });
    return parts.length ? `?${parts.join('&')}` : '';
  }

  async function call(method, path, options) {
    const { params, body, signal } = options || {};
    let response;
    try {
      response = await fetch(path + queryString(params), {
        method, signal, cache: 'no-store',
        headers: body === undefined ? { accept: 'application/json' } : { accept: 'application/json', 'content-type': 'application/json' },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (error) {
      if (error && error.name === 'AbortError') throw error;
      setLive('offline');
      throw new ApiError(0, null, 0);
    }
    const text = await response.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch (error) { data = null; }
    // The API always answers errors with a JSON problem document: a bare 404 means a static server without the API.
    if (response.status === 404 && !data) { setLive('offline'); throw new ApiError(0, null, 0); }
    if (!response.ok) throw new ApiError(response.status, data, Number(response.headers.get('retry-after')) || 0);
    if (liveState.state !== 'live') setLive('live');
    return data;
  }

  const api = {
    get: (path, params, signal) => call('GET', path, { params, signal }),
    post: (path, body, signal) => call('POST', path, { body, signal }),
  };

  /** Runs async jobs where only the newest one counts: older answers are dropped and their requests aborted. */
  function latest() {
    let counter = 0;
    let controller = null;
    return async (job) => {
      counter += 1;
      const mine = counter;
      if (controller) controller.abort();
      controller = new AbortController();
      try {
        const value = await job(controller.signal);
        return mine === counter ? { value } : null;
      } catch (error) {
        if ((error && error.name === 'AbortError') || mine !== counter) return null;
        throw error;
      }
    };
  }

  function describeApiError(error) {
    if (error.status === 0) return t('err.offline');
    if (error.status === 429) return t('err.rate', { seconds: error.retryAfter || 1 });
    const problem = error.problem;
    if (problem && Array.isArray(problem.errors) && problem.errors.length) {
      return t('err.invalid', { message: problem.errors.map(describeIssue).join(' ') });
    }
    return t('err.generic', { status: error.status, id: (problem && problem.request_id) || '–' });
  }

  /* ════════════════════════════ 4. stepper ════════════════════════════
   * Drives an explainer: events 0..total-1 are revealed one by one. The explainer renders "the state after event k",
   * so jumping, stepping back and replaying are all the same call. */
  const SPEEDS = { slow: 2.4, normal: 1, fast: 0.35 };

  const playGlyph = () => svg('svg', { viewBox: '0 0 24 24', width: 15, height: 15, fill: 'currentColor', 'aria-hidden': 'true' }, svg('path', { d: 'M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z' }));
  const pauseGlyph = () => svg('svg', { viewBox: '0 0 24 24', width: 15, height: 15, fill: 'currentColor', 'aria-hidden': 'true' }, svg('rect', { x: 6, y: 5, width: 4, height: 14, rx: 1 }), svg('rect', { x: 14, y: 5, width: 4, height: 14, rx: 1 }));

  function createStepper(explainer, options) {
    const opts = options || {};
    const total = explainer.total;
    let index = -1;
    let timer = 0;
    let playing = false;
    let speed = 'normal';
    let destroyed = false;

    const caption = el('div', { class: 'pg-caption', role: 'status', 'aria-live': 'polite' });
    const progress = el('span', { class: 'pg-controls__progress a-muted a-num' });
    const playLabel = el('span');
    const playButton = el('button', { class: 'a-btn a-btn--primary a-btn--sm', type: 'button', onclick: () => (playing ? stop() : play()) });
    const prevButton = iconButton('chevron-left', t('ctrl.prev'), () => { stop(); go(index - 1); });
    const nextButton = iconButton('chevron-right', t('ctrl.next'), () => { stop(); go(index + 1); });
    const restartButton = iconButton('refresh', t('ctrl.restart'), () => { go(-1); play(); });
    const speedSelect = el('select', { class: 'a-select pg-speed', 'aria-label': t('ctrl.speed'), onchange: (event) => { speed = event.target.value; if (playing) { stop(); play(true); } } },
      Object.keys(SPEEDS).map((key) => el('option', { value: key, selected: key === speed }, t(`ctrl.speed.${key}`))));
    const extras = [];
    if (opts.skip) extras.push(el('button', { class: 'a-btn a-btn--ghost a-btn--sm', type: 'button', onclick: () => { stop(); go(Math.min(total - 1, index + 10)); } }, t('ctrl.skip')));
    if (opts.end) extras.push(el('button', { class: 'a-btn a-btn--ghost a-btn--sm', type: 'button', onclick: () => { stop(); go(total - 1); } }, t('ctrl.end')));
    const controls = el('div', { class: 'pg-controls', role: 'group', 'aria-label': t('ctrl.group') },
      playButton, prevButton, nextButton, restartButton, extras, el('span', { class: 'a-spacer' }), progress, speedSelect);

    function refresh() {
      clear(playButton).appendChild(playing ? pauseGlyph() : playGlyph());
      playLabel.textContent = playing ? t('ctrl.pause') : (index >= total - 1 ? t('ctrl.restart') : t('ctrl.play'));
      playButton.appendChild(playLabel);
      prevButton.disabled = index < 0;
      nextButton.disabled = index >= total - 1;
      progress.textContent = t('ctrl.progress', { n: Math.max(0, index + 1), total });
      caption.setAttribute('aria-live', playing ? 'off' : 'polite');
    }

    function go(next) {
      if (destroyed) return;
      index = clamp(next, -1, total - 1);
      explainer.render(index);
      caption.textContent = explainer.caption(index);
      refresh();
    }

    function schedule() {
      timer = window.setTimeout(() => {
        if (destroyed) return;
        go(index + 1);
        if (index >= total - 1) stop(); else schedule();
      }, Math.max(16, explainer.delay(index + 1) * SPEEDS[speed]));
    }

    function play(resume) {
      if (destroyed || total === 0) return;
      if (!resume && index >= total - 1) go(-1);
      playing = true;
      refresh();
      schedule();
    }

    function stop() {
      window.clearTimeout(timer);
      playing = false;
      refresh();
    }

    return {
      controls, caption, go, play, stop,
      index: () => index,
      destroy() { destroyed = true; window.clearTimeout(timer); },
      /** Plays from the start, or jumps to the end under reduced motion. */
      autoplay() { if (sleepless()) go(total - 1); else { go(-1); play(); } },
      /** Shows a state without playing (after a language change). */
      show(at) { go(at === undefined ? total - 1 : at); },
    };
  }

  /** Puts an explainer, its caption and its controls into +container+. @returns the stepper */
  function mountExplainer(container, explainer, options) {
    const stepper = createStepper(explainer, options);
    clear(container);
    container.appendChild(el('div', { class: 'pg-stage' }, explainer.el));
    container.appendChild(stepper.caption);
    container.appendChild(stepper.controls);
    return stepper;
  }

  /* ════════════════════════════ 5. explainers ════════════════════════════
   * Each returns { el, total, render(k), caption(k), delay(k) }: render(k) paints the state after event k
   * (k = -1 is "nothing revealed yet"). They only replay data the API returned. */

  /** A grid of rows × columns; on narrow screens CSS swaps rows and columns (--col-m / --row-m). */
  function createMatrix(rows, columns) {
    const node = el('div', { class: `pg-matrix${columns > 13 ? ' pg-matrix--dense' : ''}`, 'aria-hidden': 'true', style: { '--cols': columns, '--rows': rows.length } });
    const cells = rows.map((row, r) => {
      node.appendChild(el('div', { class: 'pg-rowlabel', style: { '--col': 1, '--row': r + 1, '--col-m': r + 1, '--row-m': 1 } }, row.label));
      return row.cells.map((text, c) => {
        const cell = el('div', { class: `pg-cell ${row.className || ''}${row.hidden ? ' is-hidden' : ''}`, style: { '--col': c + 2, '--row': r + 1, '--col-m': r + 1, '--row-m': c + 2 } }, String(text));
        node.appendChild(cell);
        return cell;
      });
    });
    return { el: node, cells };
  }

  /** The same data as a table that only screen readers see (the visual grid is aria-hidden). */
  function srTable(title, rows) {
    // The clipping box is a div: a table ignores width and overflow and would widen the page on small screens.
    return el('div', { class: 'a-sr-only' }, el('table', el('caption', title),
      el('tbody', rows.map((row) => el('tr', el('th', { scope: 'row' }, row.label), row.cells.map((cell) => el('td', String(cell))))))));
  }

  /** The chips under a matrix: each appears with its event, joined by arrows. */
  function createEquation(chips) {
    const parts = [];
    const arrows = [];
    chips.forEach((chip, i) => {
      if (i > 0) {
        const arrow = el('span', { class: 'pg-eq__arrow', 'aria-hidden': 'true' }, icon('chevron-right', { size: 14 }));
        arrows.push(arrow);
        parts.push(arrow);
      }
      parts.push(chip);
    });
    return {
      el: el('div', { class: 'pg-eq' }, parts),
      reset() { chips.forEach((chip) => chip.classList.remove('is-on', 'is-active')); arrows.forEach((arrow) => arrow.classList.remove('is-on')); },
      show(i, active) {
        chips[i].classList.add('is-on');
        if (i > 0) arrows[i - 1].classList.add('is-on');
        if (active) chips[i].classList.add('is-active');
      },
    };
  }

  const chip = (text, extra) => el('span', { class: `pg-chip ${extra || ''}`.trim() }, text);
  const verdictChip = (ok, text) => { const node = Aurora.badge(text, { kind: ok ? 'good' : 'critical' }); node.classList.add('pg-chip'); return node; };

  /* ── weighted modulo 11 (CPF, CNPJ, PIS) ── */
  function mod11Block(step, s, count, alnum) {
    const n = step.chars.length;
    const letters = step.chars.map((ch, i) => String(step.values[i]) !== ch);
    let running = 0;
    const sums = step.products.map((product) => { running += product; return running; });
    const R = { char: 0, value: alnum ? 1 : -1, weight: alnum ? 2 : 1, product: alnum ? 3 : 2, running: alnum ? 4 : 3 };
    const rows = [{ label: t('row.char'), cells: step.chars, className: 'pg-cell--char' }];
    if (alnum) rows.push({ label: t('row.value'), cells: step.values, className: 'pg-cell--value' });
    rows.push({ label: t('row.weight'), cells: step.weights, className: 'pg-cell--weight' });
    rows.push({ label: t('row.product'), cells: step.products, className: 'pg-cell--product', hidden: true });
    rows.push({ label: t('row.running'), cells: sums, className: 'pg-cell--sum', hidden: true });
    const matrix = createMatrix(rows, n);
    letters.forEach((isLetter, c) => {
      if (isLetter) { matrix.cells[R.char][c].classList.add('is-letter'); matrix.cells[R.value][c].classList.add('is-letter'); }
    });
    if (s > 0) matrix.cells[R.char][n - 1].classList.add('is-check');

    const title = count === 1 ? t('block.only') : t(s === 0 ? 'block.first' : 'block.second');
    const equation = createEquation([
      chip(t('eq.sum', { sum: step.sum })),
      chip(t('eq.mod', { sum: step.sum, modulus: step.modulus, remainder: step.remainder })),
      chip(t('eq.digit', { digit: step.check_digit }), 'pg-chip--digit'),
      verdictChip(step.match, step.match ? t('eq.match') : `${t('eq.nomatch')} (${step.actual})`),
    ]);
    const node = el('section', { class: 'pg-block' },
      el('h3', { class: 'pg-block__title' }, title), matrix.el, equation.el,
      srTable(title, rows.map((row) => ({ label: row.label, cells: row.cells }))));

    return {
      el: node,
      reset() {
        matrix.cells.forEach((row) => row.forEach((cell) => cell.classList.remove('is-on', 'is-active', 'is-key')));
        equation.reset();
      },
      apply(event, active) {
        if (event.type === 'mult') {
          [R.product, R.running].forEach((r) => matrix.cells[r][event.c].classList.add('is-on'));
          if (active) matrix.cells.forEach((row) => row[event.c].classList.add('is-active'));
          return;
        }
        const at = { sum: 0, mod: 1, digit: 2, verdict: 3 }[event.type];
        equation.show(at, active);
        if (event.type === 'sum') matrix.cells[R.running][n - 1].classList.add('is-key');
      },
    };
  }

  function captionMod11(step, event) {
    switch (event.type) {
      case 'mult': {
        const ch = step.chars[event.c];
        const params = { char: ch, value: step.values[event.c], weight: step.weights[event.c], product: step.products[event.c], code: ch.charCodeAt(0) };
        return String(params.value) !== ch ? t('cap.mult.alnum', params) : t('cap.mult', params);
      }
      case 'sum': return t('cap.sum', { sum: step.sum });
      case 'mod': return t('cap.mod', { sum: step.sum, modulus: step.modulus, remainder: step.remainder });
      case 'digit':
        return step.remainder < 2
          ? t('cap.digit.zero', { remainder: step.remainder })
          : t('cap.digit.sub', { modulus: step.modulus, remainder: step.remainder, digit: step.check_digit });
      default:
        return step.match ? t('cap.verdict.ok', { actual: step.actual }) : t('cap.verdict.bad', { actual: step.actual, digit: step.check_digit });
    }
  }

  function explainMod11(steps) {
    const alnum = steps.some((step) => step.chars.some((ch, i) => String(step.values[i]) !== ch));
    const blocks = steps.map((step, s) => mod11Block(step, s, steps.length, alnum));
    const events = [];
    const firstOf = [];
    steps.forEach((step, s) => {
      firstOf[s] = events.length;
      step.chars.forEach((ch, c) => events.push({ s, type: 'mult', c }));
      ['sum', 'mod', 'digit', 'verdict'].forEach((type) => events.push({ s, type }));
    });
    const note = alnum ? el('p', { class: 'pg-note' }, icon('info', { size: 14 }), t('cap.note.alnum')) : null;
    return {
      el: el('div', { class: 'pg-explain' }, note, blocks.map((block) => block.el)),
      total: events.length,
      render(k) {
        blocks.forEach((block, s) => { block.reset(); block.el.classList.toggle('is-pending', k < firstOf[s]); });
        for (let i = 0; i <= k; i += 1) blocks[events[i].s].apply(events[i], i === k);
      },
      caption: (k) => (k < 0 ? t('cap.start.mod11') : captionMod11(steps[events[k].s], events[k])),
      delay: (i) => (events[i] && events[i].type === 'mult' ? 230 : 850),
    };
  }

  /* ── Luhn (cards) ── */
  function explainLuhn(data) {
    const entries = data.entries; // right to left
    const n = entries.length;
    const shown = entries.slice().reverse(); // left to right, as printed
    let running = 0;
    const sums = new Array(n);
    entries.forEach((entry, i) => { running += entry.contribution; sums[n - 1 - i] = running; });
    const rows = [
      { label: t('row.digit'), cells: shown.map((entry) => entry.digit), className: 'pg-cell--char' },
      { label: t('row.double'), cells: shown.map((entry) => (entry.doubled ? '×2' : '·')), className: 'pg-cell--weight' },
      { label: t('row.counts'), cells: shown.map((entry) => entry.contribution), className: 'pg-cell--product', hidden: true },
      { label: t('row.running'), cells: sums, className: 'pg-cell--sum', hidden: true },
    ];
    const matrix = createMatrix(rows, n);
    const valid = data.remainder === 0;
    const equation = createEquation([
      chip(t('eq.sum', { sum: data.sum })),
      chip(t('eq.mod', { sum: data.sum, modulus: 10, remainder: data.remainder })),
      verdictChip(valid, valid ? t('eq.valid') : t('eq.invalid')),
    ]);
    const title = t('block.luhn');
    const node = el('div', { class: 'pg-explain' }, el('section', { class: 'pg-block' },
      el('h3', { class: 'pg-block__title' }, title), matrix.el, equation.el,
      srTable(title, rows.map((row) => ({ label: row.label, cells: row.cells })))));
    const total = n + 3;

    const caption = (k) => {
      if (k < 0) return t('cap.start.luhn');
      if (k < n) {
        const entry = entries[k];
        if (!entry.doubled) return t('cap.luhn.keep', { digit: entry.digit });
        const doubled = entry.digit * 2;
        return doubled > 9 ? t('cap.luhn.double.big', { digit: entry.digit, doubled, value: entry.contribution }) : t('cap.luhn.double', { digit: entry.digit, doubled });
      }
      if (k === n) return t('cap.luhn.sum', { sum: data.sum });
      if (k === n + 1) return t('cap.luhn.mod', { sum: data.sum, remainder: data.remainder });
      return valid ? t('cap.luhn.ok') : t('cap.luhn.bad', { remainder: data.remainder });
    };

    return {
      el: node, total, caption,
      render(k) {
        matrix.cells.forEach((row) => row.forEach((cell) => cell.classList.remove('is-on', 'is-active', 'is-key')));
        equation.reset();
        for (let i = 0; i <= k; i += 1) {
          const active = i === k;
          if (i < n) {
            const c = n - 1 - i;
            [2, 3].forEach((r) => matrix.cells[r][c].classList.add('is-on'));
            if (active) matrix.cells.forEach((row) => row[c].classList.add('is-active'));
          } else {
            equation.show(i - n, active);
            if (i === n) matrix.cells[3][0].classList.add('is-key');
          }
        }
      },
      delay: (i) => (i < n ? 300 : 850),
    };
  }

  /* ── narrative explainers (plate, phone, CEP): highlighted tokens plus the findings so far ── */
  function explainTokens(spec) {
    const tokens = spec.tokens.map((token) => ({ ...token, node: el('div', { class: 'pg-token' }, token.text) }));
    const row = el('div', { class: 'pg-tokens', 'aria-hidden': 'true' }, tokens.map((token) => el('div', { class: 'pg-token-wrap' }, token.node, el('span', { class: 'pg-token__label' }, token.label || ''))));
    const found = el('div', { class: 'pg-found' });
    const node = el('div', { class: 'pg-explain pg-explain--tokens' }, row, spec.extra ? spec.extra.el : null, found,
      el('p', { class: 'a-sr-only' }, spec.events.map((event) => event.caption).join(' ')));
    return {
      el: node, total: spec.events.length,
      render(k) {
        clear(found);
        tokens.forEach((token) => { token.node.classList.remove('is-on', 'is-active', 'is-flipped'); token.node.textContent = token.text; });
        for (let i = 0; i <= k; i += 1) {
          const event = spec.events[i];
          event.ids.forEach((id) => { tokens[id].node.classList.add('is-on'); if (i === k) tokens[id].node.classList.add('is-active'); });
          (event.swap || []).forEach((swap) => { tokens[swap.id].node.textContent = swap.text; tokens[swap.id].node.classList.add('is-flipped'); });
          (event.found || []).forEach((fact) => found.appendChild(el('span', { class: 'pg-fact' }, el('span', { class: 'a-faint' }, fact.label), mono(fact.value))));
        }
        if (spec.extra) spec.extra.render(k);
      },
      caption: (k) => (k < 0 ? spec.intro : spec.events[k].caption),
      delay: () => 1500,
    };
  }

  const LETTERS_AJ = 'ABCDEFGHIJ';

  /** The 0→A … 9→J table of the plate conversion, with the column of +digit+ lit from event +from+ on. */
  function plateMap(digit, from) {
    const cells = [];
    const grid = el('div', { class: 'pg-map', 'aria-hidden': 'true' });
    for (let d = 0; d < 10; d += 1) {
      const top = el('div', { class: 'pg-cell pg-cell--char' }, String(d));
      const bottom = el('div', { class: 'pg-cell pg-cell--weight' }, LETTERS_AJ[d]);
      grid.appendChild(el('div', { class: 'pg-map__col' }, top, bottom));
      cells.push(top, bottom);
    }
    return {
      el: grid,
      render(k) { cells.forEach((cell, i) => cell.classList.toggle('is-active', k >= from && Math.floor(i / 2) === digit)); },
    };
  }

  function explainPlate(result, conversion) {
    const plate = result.normalized;
    const base = plate.split('').map((ch, i) => ({ text: ch, label: String(i + 1) }));
    const all = base.map((token, i) => i);
    if (result.details.layout === 'legacy') {
      if (!conversion) return null; // the conversion call failed: nothing true to show
      const { digit, letter, position } = conversion.details.conversion;
      const at = position - 1;
      return explainTokens({
        tokens: base, intro: t('cap.plate.0'), extra: plateMap(Number(digit), 2),
        events: [
          { ids: all, caption: t('cap.plate.0') },
          { ids: [at], caption: t('cap.plate.1') },
          { ids: [at], caption: t('cap.plate.2', { digit, letter }) },
          { ids: [at], caption: t('cap.plate.3', { plate: conversion.normalized }), swap: [{ id: at, text: letter }], found: [{ label: 'Mercosul', value: conversion.normalized }] },
        ],
      });
    }
    return explainTokens({
      tokens: base, intro: t('cap.plate.m0'),
      events: [
        { ids: all, caption: t('cap.plate.m0') },
        { ids: [4], caption: t('cap.plate.m1') },
      ],
    });
  }

  function explainPhone(result) {
    const d = result.details;
    const digits = result.normalized.replace(/\D/g, '');
    const number = `${d.number.slice(0, -4)}-${d.number.slice(-4)}`;
    const typeText = t(`fact.type.${d.type}`);
    return explainTokens({
      tokens: [{ text: '+55', label: t('tok.country') }, { text: d.area_code, label: t('tok.area') }, { text: number, label: t('tok.number') }],
      intro: t('cap.phone.0', { digits }),
      events: [
        { ids: [0, 1, 2], caption: t('cap.phone.0', { digits }) },
        { ids: [1], caption: t('cap.phone.1', { area: d.area_code, uf: d.uf }), found: [{ label: t('gen.uf'), value: d.uf }] },
        { ids: [2], caption: t(`cap.phone.${d.type}`, { number: d.number }), found: [{ label: t('fact.type'), value: typeText }] },
        { ids: [0], caption: t('cap.phone.2', { e164: result.normalized }), found: [{ label: 'E.164', value: result.normalized }] },
      ],
    });
  }

  function explainCep(result) {
    const digits = result.normalized;
    const region = digits[0];
    const prefix = digits.slice(0, 5);
    const uf = result.details.uf || '–';
    return explainTokens({
      tokens: [{ text: digits[0], label: t('tok.region') }, { text: digits.slice(1, 5), label: t('tok.prefix') }, { text: '-', label: '' }, { text: digits.slice(5), label: t('tok.suffix') }],
      intro: t('cap.cep.0'),
      events: [
        { ids: [0, 1, 3], caption: t('cap.cep.0') },
        { ids: [0], caption: t('cap.cep.1', { digit: region, regions: t(`cep.region.${region}`) }), found: [{ label: t('tok.region'), value: `${region} · ${t(`cep.region.${region}`)}` }] },
        { ids: [0, 1], caption: t('cap.cep.2', { prefix, uf }), found: [{ label: t('gen.uf'), value: uf }] },
        { ids: [], caption: t('cap.cep.3') },
      ],
    });
  }

  /* ── PIX: CRC-16/CCITT-FALSE over the payload ── */
  function explainCrc(result) {
    const crc = result.details.crc;
    const steps = crc.steps;
    const n = steps.length;
    const tape = el('div', { class: 'pg-tape', 'aria-hidden': 'true' }, steps.map((step) => el('span', { class: 'pg-tape__c' }, printable(step.byte))));
    const tapeCells = Array.from(tape.children);
    const tail = el('span', { class: 'pg-tape__crc' }, crc.actual);
    tape.appendChild(tail);

    const display = {};
    const box = (key, label) => {
      const value = el('span', { class: 'pg-reg__value a-mono' }, '–');
      display[key] = value;
      return el('div', { class: 'pg-reg__box' }, el('span', { class: 'pg-reg__label' }, label), value);
    };
    const registers = el('div', { class: 'pg-reg', 'aria-hidden': 'true' },
      box('byte', t('crc.byte')), box('before', t('crc.before')), box('index', t('crc.index')), box('table', t('crc.table')), box('after', t('crc.reg')));
    /** Sets a box to one line, or to an operation and, on its own line, its result. */
    const setBox = (key, first, second) => {
      display[key].textContent = first;
      if (second) display[key].appendChild(el('span', { class: 'pg-reg__result' }, `= ${second}`));
    };
    const match = crc.valid;
    const finale = createEquation([
      chip(t('crc.final', { crc: crc.expected })),
      chip(t('crc.carried', { crc: crc.actual })),
      verdictChip(match, match ? t('eq.match') : t('eq.nomatch')),
    ]);

    let painted = [];
    const paintTape = (k) => {
      tapeCells.forEach((cell, i) => {
        const state = k > n - 1 || i < k ? 1 : (i === k ? 2 : 0);
        if (painted[i] === state) return;
        painted[i] = state;
        cell.classList.toggle('is-done', state === 1);
        cell.classList.toggle('is-current', state === 2);
      });
      tail.classList.toggle('is-on', k >= n);
    };

    return {
      el: el('div', { class: 'pg-explain pg-explain--crc' }, tape, registers, finale.el),
      total: n + 1,
      render(k) {
        paintTape(k);
        finale.reset();
        const at = clamp(k, 0, n - 1);
        if (k < 0) {
          ['byte', 'index', 'table', 'after'].forEach((key) => setBox(key, '–'));
          setBox('before', hex(0xFFFF, 4));
          return;
        }
        const step = steps[at];
        const before = at === 0 ? 0xFFFF : steps[at - 1].crc;
        setBox('byte', `${printable(step.byte)} · 0x${hex(step.byte)}`);
        setBox('before', hex(before, 4));
        setBox('index', `${hex(before >> 8)} XOR ${hex(step.byte)}`, hex(step.index));
        setBox('table', `0x${hex(step.table, 4)}`);
        setBox('after', `${hex((before << 8) & 0xFFFF, 4)} XOR ${hex(step.table, 4)}`, hex(step.crc, 4));
        if (k >= n) { [0, 1, 2].forEach((i) => finale.show(i, i === 2)); }
      },
      caption(k) {
        if (k < 0) return t('crc.intro');
        if (k < n) return t('crc.cap.step', { n: k + 1, total: n, char: `"${printable(steps[k].byte)}"`, hex: hex(steps[k].byte) });
        return match ? t('crc.cap.end.ok', { crc: crc.actual }) : t('crc.cap.end.bad', { expected: crc.expected, actual: crc.actual });
      },
      delay: (i) => (i < n ? 75 : 900),
    };
  }

  /* ════════════════════════════ 6. shared panels ════════════════════════════ */
  const catalog = { uf: [], brand: [], ddd: [] };
  const BRAND_NAMES = { elo: 'Elo', hipercard: 'Hipercard', hiper: 'Hiper', amex: 'American Express', diners: 'Diners Club', jcb: 'JCB', mastercard: 'Mastercard', visa: 'Visa', discover: 'Discover', unionpay: 'UnionPay' };

  /** Reads the option lists (states, brands, area codes) from the API's own OpenAPI description. */
  async function loadCatalog() {
    try {
      const spec = await api.get('/api/v1/openapi.json');
      const enumOf = (path, name) => {
        const parameters = (spec.paths[path] && spec.paths[path].get.parameters) || [];
        const found = parameters.find((parameter) => parameter.name === name);
        return (found && found.schema.enum) || [];
      };
      catalog.uf = enumOf('/api/v1/cpf/generate', 'uf');
      catalog.brand = enumOf('/api/v1/card/generate', 'brand');
      catalog.ddd = enumOf('/api/v1/phone/generate', 'ddd');
    } catch (error) { /* the selects stay empty: the API is unreachable anyway */ }
  }

  /** A card with a header; @returns { el, body } */
  function card(options) {
    const head = el('div', { class: 'a-card__head' },
      el('div', null, el('h2', { class: 'a-card__title' }, options.title), options.sub ? el('div', { class: 'a-card__sub' }, options.sub) : null),
      options.actions ? el('div', { class: 'a-card__actions' }, options.actions) : null);
    const body = el('div', { class: 'a-card__body pg-body' });
    return { el: el('section', { class: `a-card ${options.className || ''}`.trim() }, head, body), body };
  }

  const chipButton = (text, onClick) => el('button', { class: 'a-chip', type: 'button', onclick: onClick }, text);

  /** The primary input of a tool, in Aurora's composer: a label, the input, a hint and the shortcut chips. */
  function composer(options) {
    return el('div', { class: 'a-composer pg-composer' },
      el('label', { class: 'a-label', for: options.input.id }, options.label),
      options.input,
      el('div', { class: 'a-composer__bar' },
        el('p', { class: 'pg-composer__hint', id: options.hintId }, options.hint),
        el('div', { class: 'pg-chips' }, options.chips)));
  }

  /** The card that answers a composer: the verdict is its header band, the facts list sits under it. */
  function resultCard() {
    const verdict = el('div', { class: 'pg-verdict-slot', 'aria-live': 'polite' });
    const facts = el('div', { class: 'pg-facts' });
    return { el: el('section', { class: 'a-card pg-answer', role: 'group', 'aria-label': t('result.title') }, verdict, facts), verdict, facts };
  }

  function labelled(id, label, control, hint) {
    return el('div', { class: 'a-field' }, el('label', { for: id }, label), control, hint ? el('span', { class: 'a-field__hint' }, hint) : null);
  }

  function selectControl(id, items, value, onChange) {
    return el('select', { class: 'a-select', id, onchange: (event) => onChange(event.target.value) },
      items.map(([optionValue, text]) => el('option', { value: optionValue, selected: optionValue === value }, text)));
  }

  function switchControl(id, label, checked, onChange) {
    return el('label', { class: 'pg-switch', for: id }, el('input', { class: 'a-switch', type: 'checkbox', role: 'switch', id, checked, onchange: (event) => onChange(event.target.checked) }), el('span', label));
  }

  function numberControl(id, value, min, max, onChange, placeholder) {
    return el('input', { class: 'a-input', type: 'number', id, value, min, max, step: 1, inputmode: 'numeric', placeholder: placeholder || null, oninput: (event) => onChange(event.target.value) });
  }

  /** A notice with an icon: information the reader must not miss (fictitious data, test numbers). */
  const notice = (text, kind, title) => el('p', { class: `pg-notice pg-notice--${kind || 'info'}`, role: 'note' },
    icon(kind === 'warn' ? 'alert' : 'info', { size: 16 }), el('span', title ? el('strong', `${title} `) : null, text));

  function emptyState(parent, title, text) {
    Aurora.empty(parent, { title, text, icon: 'sparkle' });
  }

  /** How many characters were given when the only problem is a value that is still too short (the person is typing). */
  function tooShort(result) {
    if (result.errors.length !== 1 || result.errors[0].code !== 'invalid_length') return null;
    const message = result.errors[0].message;
    const got = Number((message.match(/got (\d+)/) || [])[1]);
    const wanted = Math.max(0, ...(message.split('got')[0].match(/\d+/g) || []).map(Number));
    return got < wanted ? got : null;
  }

  const VERDICT_ICONS = { good: 'check-circle', bad: 'x-circle', warn: 'alert', empty: 'sparkle' };

  /** A verdict (kind: good, bad, warn or empty): an icon tile plus words, never colour alone, with optional reasons. */
  function verdictNode(kind, title, text, reasons) {
    return el('div', { class: `pg-verdict pg-verdict--${kind}` },
      el('span', { class: 'pg-verdict__icon' }, icon(VERDICT_ICONS[kind], { size: 18 })),
      el('div', { class: 'pg-verdict__text' },
        el('strong', { class: 'pg-verdict__title' }, title),
        text ? el('span', { class: 'pg-verdict__sub' }, text) : null,
        reasons && reasons.length ? el('ul', { class: 'pg-reasons' }, reasons.map((reason) => el('li', reason))) : null));
  }

  /* ════════════════════════════ 7. document tabs ════════════════════════════ */
  const DOCS = {
    cpf: { param: 'cpf', explain: 'mod11', valid: '529.982.247-25', invalid: '529.982.247-26', placeholder: '000.000.000-00', generate: ['uf', 'formatted'] },
    cnpj: { param: 'cnpj', explain: 'mod11', valid: '12.ABC.345/01DE-35', invalid: '11.222.333/0001-82', placeholder: '00.000.000/0000-00', generate: ['alphanumeric', 'branch', 'formatted'] },
    card: { param: 'number', explain: 'luhn', valid: '4111 1111 1111 1111', invalid: '4111 1111 1111 1112', placeholder: '0000 0000 0000 0000', generate: ['brand'], warn: 'gen.warn.card' },
    plate: { param: 'plate', explain: 'plate', valid: 'ABC-1234', invalid: 'AB-1234', placeholder: 'AAA-0000', generate: ['layout', 'formatted'], feminine: true },
    phone: { param: 'phone', explain: 'phone', valid: '(11) 98765-4321', invalid: '(11) 8765-4321', placeholder: '(00) 00000-0000', generate: ['uf', 'ddd', 'type', 'formatted'], warn: 'gen.warn.phone' },
    cep: { param: 'cep', explain: 'cep', valid: '01310-100', invalid: '1234', placeholder: '00000-000', generate: ['uf', 'formatted'] },
  };

  const defaultOptions = () => ({ uf: '', ddd: '', formatted: true, alphanumeric: true, branch: '0001', brand: '', layout: 'mercosul', type: 'mobile', count: 3, seed: '' });

  function factsFor(id, result) {
    const d = result.details || {};
    const rows = [];
    const add = (label, value) => { if (value !== undefined && value !== null && value !== '') rows.push([label, value]); };
    const yesNo = (flag) => t(flag ? 'fact.yes' : 'fact.no');
    add(t('fact.normalized'), result.normalized && mono(result.normalized));
    if (id !== 'card' && result.formatted && result.formatted !== result.normalized) add(t('fact.formatted'), mono(result.formatted));
    switch (id) {
      case 'cpf':
        if (d.ufs) add(t('fact.region'), `${d.region_digit} · ${d.ufs.join(', ')}`);
        break;
      case 'cnpj':
        add(t('fact.root'), d.root && mono(d.root));
        add(t('fact.branch'), d.branch && mono(d.branch));
        add(t('fact.checkdigits'), d.check_digits && mono(d.check_digits));
        if (d.root) { add(t('fact.kind'), t(d.alphanumeric ? 'fact.kind.alnum' : 'fact.kind.numeric')); add(t('fact.hq'), yesNo(d.headquarters)); }
        break;
      case 'card':
        add(t('fact.formatted'), result.formatted && mono(result.formatted));
        add(t('fact.brand'), d.brand_name);
        add(t('fact.bin'), d.bin && mono(d.bin));
        add(t('fact.last4'), d.last4 && mono(d.last4));
        if (d.length) add(t('fact.length'), t('fact.length.value', { n: d.length }));
        add(t('fact.cvv'), d.cvv_length ? t('fact.length.value', { n: d.cvv_length }) : null);
        if (d.test_number) add(t('fact.test'), yesNo(true));
        break;
      case 'plate':
        add(t('fact.layout'), d.layout && t(`fact.layout.${d.layout}`));
        add(t('fact.mercosul'), d.mercosul && mono(d.mercosul));
        break;
      case 'phone':
        add(t('fact.intl'), d.international && mono(d.international));
        add(t('fact.area'), d.area_code && `${d.area_code} · ${d.uf}`);
        add(t('fact.type'), d.type && t(`fact.type.${d.type}`));
        break;
      case 'cep':
        add(t('gen.uf'), d.uf);
        if (d.region_digit !== undefined) add(t('fact.postal'), `${d.region_digit} · ${t(`cep.region.${d.region_digit}`)}`);
        break;
      default: break;
    }
    return rows;
  }

  /** The explainer for the current result, or null when there is nothing to replay. */
  function explainerFor(id, result, conversion) {
    if (!result) return null;
    const kind = DOCS[id].explain;
    const steps = result.details && result.details.steps;
    if (kind === 'mod11') return Array.isArray(steps) && steps.length ? explainMod11(steps) : null;
    if (kind === 'luhn') return steps && steps.entries ? explainLuhn(steps) : null;
    if (!result.valid) return null;
    if (kind === 'plate') return explainPlate(result, conversion);
    if (kind === 'phone') return explainPhone(result);
    return explainCep(result);
  }

  function generatorParams(id, opts) {
    const params = { count: opts.count, seed: opts.seed };
    DOCS[id].generate.forEach((name) => {
      const value = opts[name];
      params[name] = typeof value === 'boolean' ? String(value) : value;
    });
    return params;
  }

  /** Validate, explain and generate for one document: the layout shared by CPF, CNPJ, card, plate, phone and CEP. */
  function createDocTab(id) {
    const doc = DOCS[id];
    const state = { value: doc.valid, result: null, conversion: null, error: null, busy: false, items: null, seed: null, genError: null, opts: defaultOptions() };
    const root = el('div', { class: 'a-grid pg-tab pg-tab--explain' });
    const runValidate = latest();
    const runGenerate = latest();
    let stepper = null;
    let built = false;
    let ui = {};

    const docName = () => t(`doc.name.${id}`);

    function renderVerdict() {
      const box = clear(ui.verdict);
      ui.verdict.classList.toggle('a-refreshing', state.busy);
      if (state.error) { box.appendChild(notice(describeApiError(state.error), 'warn')); return; }
      const result = state.result;
      if (!state.value.trim() || !result) {
        const typed = state.value.trim() !== '';
        box.appendChild(verdictNode('empty', t(typed ? 'verdict.checking' : 'verdict.empty.title'), typed ? null : t('verdict.empty.text')));
        return;
      }
      const suffix = doc.feminine ? '.f' : '';
      const title = (key) => cap(t(`${key}${suffix}`, { doc: docName() }));
      const short = result.valid ? null : tooShort(result);
      if (result.valid) box.appendChild(verdictNode('good', title('verdict.valid'), t(`verdict.ok.${id}`)));
      else if (short) box.appendChild(verdictNode('warn', title('verdict.incomplete'), t('verdict.incomplete.text', { got: short })));
      else box.appendChild(verdictNode('bad', title('verdict.invalid'), null, result.errors.map(describeIssue)));
    }

    function renderFacts() {
      const box = clear(ui.facts);
      ui.facts.classList.toggle('a-refreshing', state.busy);
      if (!state.result || !state.value.trim()) return;
      const rows = factsFor(id, state.result);
      if (rows.length) Aurora.kv(box, rows);
    }

    function renderExplain(play) {
      if (stepper) stepper.destroy();
      stepper = null;
      const explainer = state.error ? null : explainerFor(id, state.result, state.conversion);
      if (!explainer) {
        clear(ui.explain);
        emptyState(ui.explain, t('explain.empty.title'), t('explain.empty.text'));
        return;
      }
      stepper = mountExplainer(ui.explain, explainer);
      if (play) stepper.autoplay(); else stepper.show();
    }

    async function validateNow(play) {
      const value = state.value;
      if (!value.trim()) {
        state.result = null; state.conversion = null; state.error = null; state.busy = false;
        renderVerdict(); renderFacts(); renderExplain(false);
        return;
      }
      state.busy = true;
      ui.verdict.classList.add('a-refreshing');
      try {
        const outcome = await runValidate(async (signal) => {
          const result = await api.get(`/api/v1/${id}/validate`, { [doc.param]: value, explain: doc.explain === 'mod11' || doc.explain === 'luhn' ? 'true' : undefined }, signal);
          let conversion = null;
          if (id === 'plate' && result.valid && result.details.layout === 'legacy') conversion = await api.get('/api/v1/plate/convert', { plate: value }, signal);
          return { result, conversion };
        });
        if (!outcome) return;
        state.result = outcome.value.result;
        state.conversion = outcome.value.conversion;
        state.error = null;
      } catch (error) {
        state.error = error;
        state.result = null;
        state.conversion = null;
        if (error.status === 429) Aurora.toast(describeApiError(error), { kind: 'warn' });
      }
      state.busy = false;
      renderVerdict(); renderFacts(); renderExplain(play);
    }

    const validateSoon = Aurora.debounce(() => validateNow(true), 300);

    function setValue(value, immediate) {
      state.value = value;
      ui.input.value = value;
      if (immediate) validateNow(true); else validateSoon();
    }

    /* — generator — */
    function renderResults() {
      const box = clear(ui.results);
      if (state.genError) { box.appendChild(notice(describeApiError(state.genError), 'warn')); return; }
      if (!state.items) { box.appendChild(el('p', { class: 'a-muted a-faint' }, t('gen.empty'))); return; }
      const list = el('ul', { class: 'pg-results' });
      state.items.forEach((item) => {
        const text = typeof item === 'string' ? item : item.formatted;
        const raw = typeof item === 'string' ? item : item.number;
        list.appendChild(el('li', { class: 'pg-result' },
          el('span', { class: 'pg-result__value a-mono a-num' }, text),
          typeof item === 'string' ? null : el('span', { class: 'a-tag' }, item.brand_name),
          el('span', { class: 'a-spacer' }),
          el('button', { class: 'a-btn a-btn--ghost a-btn--sm', type: 'button', onclick: () => { setValue(raw, true); ui.input.focus({ preventScroll: true }); ui.composer.scrollIntoView({ block: 'nearest' }); } }, t('gen.validate')),
          copyButton(text, `${t('gen.copy')}: ${text}`)));
      });
      box.appendChild(list);
      box.appendChild(el('div', { class: 'pg-results__foot' },
        el('span', { class: 'a-faint' }, t('gen.seedused', { seed: state.seed })),
        el('button', { class: 'a-btn a-btn--ghost a-btn--sm', type: 'button', onclick: () => copyText(state.items.map((item) => (typeof item === 'string' ? item : item.formatted)).join('\n')) }, t('gen.copyall'))));
    }

    async function generateNow() {
      ui.generate.disabled = true;
      try {
        const outcome = await runGenerate((signal) => api.get(`/api/v1/${id}/generate`, generatorParams(id, state.opts), signal));
        if (!outcome) return;
        state.items = outcome.value.items;
        state.seed = outcome.value.seed;
        state.genError = null;
      } catch (error) {
        state.genError = error;
        state.items = null;
        if (error.status === 429) Aurora.toast(describeApiError(error), { kind: 'warn' });
      }
      ui.generate.disabled = false;
      renderResults();
    }

    function optionFields() {
      const opts = state.opts;
      const uid = Aurora.uid(`${id}-opt`);
      const anyOption = [['', t('gen.any')]];
      const fields = {
        uf: () => labelled(`${uid}-uf`, t('gen.uf'), selectControl(`${uid}-uf`, anyOption.concat(catalog.uf.map((uf) => [uf, uf])), opts.uf, (value) => { opts.uf = value; })),
        ddd: () => labelled(`${uid}-ddd`, t('gen.ddd'), selectControl(`${uid}-ddd`, anyOption.concat(catalog.ddd.map((ddd) => [ddd, ddd])), opts.ddd, (value) => { opts.ddd = value; })),
        brand: () => labelled(`${uid}-brand`, t('gen.brand'), selectControl(`${uid}-brand`, anyOption.concat(catalog.brand.map((brand) => [brand, BRAND_NAMES[brand] || cap(brand)])), opts.brand, (value) => { opts.brand = value; })),
        layout: () => labelled(`${uid}-layout`, t('gen.layout'), selectControl(`${uid}-layout`, [['mercosul', t('gen.layout.mercosul')], ['legacy', t('gen.layout.legacy')]], opts.layout, (value) => { opts.layout = value; })),
        type: () => labelled(`${uid}-type`, t('gen.type'), selectControl(`${uid}-type`, [['mobile', t('gen.type.mobile')], ['landline', t('gen.type.landline')]], opts.type, (value) => { opts.type = value; })),
        branch: () => labelled(`${uid}-branch`, t('gen.branch'), el('input', { class: 'a-input a-mono', id: `${uid}-branch`, type: 'text', value: opts.branch, maxlength: 4, spellcheck: 'false', autocomplete: 'off', oninput: (event) => { opts.branch = event.target.value.trim(); } })),
        formatted: () => switchControl(`${uid}-formatted`, t('gen.formatted'), opts.formatted, (checked) => { opts.formatted = checked; }),
        alphanumeric: () => switchControl(`${uid}-alnum`, t('gen.alnum'), opts.alphanumeric, (checked) => { opts.alphanumeric = checked; }),
      };
      const nodes = doc.generate.filter((name) => name !== 'formatted' && name !== 'alphanumeric').map((name) => fields[name]());
      nodes.push(labelled(`${uid}-count`, t('gen.count'), numberControl(`${uid}-count`, opts.count, 1, 20, (value) => { opts.count = value; })));
      nodes.push(labelled(`${uid}-seed`, t('gen.seed'), numberControl(`${uid}-seed`, opts.seed, 0, 4294967295, (value) => { opts.seed = value; }, t('gen.seed.hint'))));
      const switches = doc.generate.filter((name) => name === 'formatted' || name === 'alphanumeric').map((name) => fields[name]());
      return [el('div', { class: 'pg-options' }, nodes), switches.length ? el('div', { class: 'pg-switches' }, switches) : null];
    }

    /* — layout — */
    function build() {
      if (stepper) stepper.destroy();
      stepper = null;
      clear(root);
      const inputId = Aurora.uid(`${id}-in`);
      const hintId = `${inputId}-hint`;
      const input = el('input', { class: 'a-composer__input pg-composer__value', id: inputId, type: 'text', value: state.value, placeholder: doc.placeholder, maxlength: 64, autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false', 'aria-describedby': hintId, oninput: (event) => { state.value = event.target.value; validateSoon(); } });
      const answer = resultCard();
      ui = { input, verdict: answer.verdict, facts: answer.facts, explain: el('div', { class: 'pg-explain-slot' }), results: el('div', { class: 'pg-results-slot' }) };
      ui.generate = el('button', { class: 'a-btn a-btn--primary', type: 'button', onclick: generateNow }, icon('bolt', { size: 16 }), t('gen.button'));
      ui.composer = composer({
        label: t(`doc.label.${id}`), input, hint: t(`doc.hint.${id}`), hintId,
        chips: [
          chipButton(t('validate.example.valid'), () => setValue(doc.valid, true)),
          chipButton(t('validate.example.invalid'), () => setValue(doc.invalid, true)),
          chipButton(t('validate.clear'), () => { setValue('', true); input.focus(); }),
        ],
      });

      const explainCard = card({ title: t('explain.title'), sub: t(`explain.sub.${doc.explain}`), className: 'a-span-7 pg-rows-2' });
      explainCard.body.appendChild(ui.explain);

      const generateCard = card({ title: t('gen.title', { doc: docName() }), sub: t('gen.sub'), className: 'a-span-5' });
      generateCard.body.append(...[...optionFields(), el('div', { class: 'pg-actions' }, ui.generate), doc.warn ? notice(t(doc.warn), 'warn') : null, ui.results].filter(Boolean));

      root.append(el('div', { class: 'a-span-5 pg-column' }, ui.composer, answer.el), explainCard.el, generateCard.el);
      built = true;
      renderVerdict(); renderFacts(); renderExplain(false); renderResults();
    }

    return {
      el: root,
      activate() {
        if (built) return;
        build();
        if (apiDown()) {
          state.error = unreachable(); state.genError = state.error;
          renderVerdict(); renderFacts(); renderExplain(false); renderResults();
          return;
        }
        validateNow(true);
        generateNow();
      },
      deactivate() { if (stepper) stepper.stop(); },
      rebuild() { if (built) build(); },
      generate() { if (built) generateNow(); },
      replay() { if (stepper) stepper.autoplay(); },
      useExample() { if (built) setValue(doc.valid, true); },
    };
  }

  /* ════════════════════════════ 8. PIX tab ════════════════════════════ */
  // The static example printed in the Banco Central BR Code manual (CRC 1D3D).
  const BCB_EXAMPLE = '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D';
  const PIX_FIELDS = ['key', 'key_type', 'name', 'city', 'amount', 'txid', 'message'];

  /** The TLV tree of a decoded BR Code: id, meaning, length and value of every field. */
  function tlvTree(fields, parentId) {
    const list = el('ul', { class: 'pg-tlv' });
    fields.forEach((field) => {
      let nameKey = `tlv.root.${field.id}`;
      if (parentId !== undefined) nameKey = parentId === '62' ? `tlv.a.${field.id}` : `tlv.m.${field.id}`;
      let name = MESSAGES.pt[nameKey] !== undefined ? t(nameKey) : field.name;
      if (parentId === undefined && Number(field.id) >= 26 && Number(field.id) <= 51) name = t('tlv.merchant');
      const row = el('div', { class: 'pg-tlv__row' },
        el('span', { class: 'pg-tlv__id a-mono' }, field.id),
        el('span', { class: 'pg-tlv__name' }, name),
        el('span', { class: 'pg-tlv__len a-faint a-num' }, t('pix.tree.len', { n: field.length })),
        field.children ? null : el('span', { class: 'pg-tlv__value a-mono' }, field.value));
      list.appendChild(el('li', { class: 'pg-tlv__item' }, row, field.children ? tlvTree(field.children, field.id) : null));
    });
    return list;
  }

  /** The next character of the same kind: 9 wraps to 0, z to a, Z to A. */
  function nextChar(ch) {
    if (ch === '9') return '0';
    if (ch === 'z') return 'a';
    if (ch === 'Z') return 'A';
    return String.fromCharCode(ch.charCodeAt(0) + 1);
  }

  /** Changes one character inside the merchant name (or the first letter or digit) so only the CRC stops matching. */
  function tamper(text, decoded) {
    const name = decoded && decoded.details && decoded.details.pix && decoded.details.pix.merchant_name;
    let at = name ? text.indexOf(name) : -1;
    if (at < 0) at = text.search(/[0-9a-zA-Z]/);
    if (at < 0) return text;
    return text.slice(0, at) + nextChar(text.charAt(at)) + text.slice(at + 1);
  }

  function createPixTab() {
    const state = {
      form: { key: '123e4567-e12b-12d1-a456-426655440000', key_type: '', name: 'Fulano de Tal', city: 'BRASILIA', amount: '', txid: '', message: '' },
      built: null, fieldErrors: {}, buildError: null,
      text: BCB_EXAMPLE, linked: true, decoded: null, decodeError: null, busy: false,
    };
    const root = el('div', { class: 'a-grid pg-tab' });
    const runBuild = latest();
    const runDecode = latest();
    let stepper = null;
    let built = false;
    let ui = {};

    /* — builder — */
    function renderBuilt() {
      const box = clear(ui.built);
      PIX_FIELDS.forEach((name) => { if (ui.errors[name]) ui.errors[name].textContent = (state.fieldErrors[name] || []).join(' '); if (ui.inputs[name]) ui.inputs[name].setAttribute('aria-invalid', state.fieldErrors[name] ? 'true' : 'false'); });
      if (state.buildError) { box.appendChild(notice(describeApiError(state.buildError), 'warn')); return; }
      if (Object.keys(state.fieldErrors).length) { box.appendChild(notice(t('pix.build.error'), 'warn')); return; }
      if (!state.built) return;
      const payload = state.built.payload;
      box.append(
        el('div', { class: 'pg-codehead' }, el('span', { class: 'a-label' }, t('pix.built')), el('span', { class: 'a-spacer' }),
          el('span', { class: 'a-tag' }, t('pix.crc', { crc: state.built.crc })), el('span', { class: 'a-tag' }, t('pix.keytype.detected', { type: t(`pix.keytype.${state.built.key_type}`) })), copyButton(payload, t('pix.copy'))),
        el('pre', { class: 'a-code a-code--wrap', tabindex: '0' }, el('code', payload)),
        el('div', { class: 'pg-actions' }, el('button', { class: 'a-btn a-btn--sm', type: 'button', onclick: () => { state.linked = true; setText(payload, true); } }, t('pix.todecoder'))));
    }

    async function buildNow() {
      const body = {};
      PIX_FIELDS.forEach((name) => { const value = state.form[name].trim(); if (value) body[name] = value; });
      try {
        const outcome = await runBuild((signal) => api.post('/api/v1/pix/payload', body, signal));
        if (!outcome) return;
        state.built = outcome.value; state.fieldErrors = {}; state.buildError = null;
        if (state.linked) setText(state.built.payload, true);
      } catch (error) {
        state.built = null; state.fieldErrors = {}; state.buildError = null;
        const issues = error.problem && Array.isArray(error.problem.errors) ? error.problem.errors : [];
        if (error.status === 422 && issues.length) {
          issues.forEach((issue) => { const name = issue.field || 'key'; (state.fieldErrors[name] = state.fieldErrors[name] || []).push(describeIssue(issue)); });
        } else {
          state.buildError = error;
          if (error.status === 429) Aurora.toast(describeApiError(error), { kind: 'warn' });
        }
      }
      renderBuilt();
    }
    const buildSoon = Aurora.debounce(buildNow, 350);

    /* — decoder — */
    function renderDecoded(play) {
      const box = clear(ui.decoded);
      const facts = clear(ui.facts);
      const tree = clear(ui.tree);
      [ui.decoded, ui.facts, ui.tree].forEach((node) => node.classList.toggle('a-refreshing', state.busy));
      if (stepper) stepper.destroy();
      stepper = null;
      const result = state.decoded;
      if (state.decodeError) box.appendChild(notice(describeApiError(state.decodeError), 'warn'));
      else if (!result) box.appendChild(verdictNode('empty', t('pix.decode.empty')));
      else {
        const crc = result.details.crc;
        const reasons = result.errors.map(describeIssue);
        // A CRC mismatch is already in the reasons; the sentence is only for the good news.
        const text = crc && crc.valid ? t('pix.decode.crc.ok', { crc: crc.actual }) : null;
        box.appendChild(verdictNode(result.valid ? 'good' : 'bad', t(result.valid ? 'pix.decode.valid' : 'pix.decode.invalid'), text, result.valid ? [] : reasons));
        const pix = result.details.pix;
        if (pix) {
          const keyType = pix.key_type ? t(`pix.keytype.${pix.key_type}`) : null;
          const rows = [[t('pix.facts.key'), pix.key && mono(pix.key)], [t('pix.facts.keytype'), keyType], [t('pix.facts.merchant'), pix.merchant_name], [t('pix.facts.city'), pix.merchant_city],
            [t('pix.facts.amount'), pix.amount ? mono(pix.amount) : t('pix.facts.open')], [t('pix.facts.txid'), pix.txid && mono(pix.txid)], [t('pix.facts.message'), pix.message]];
          Aurora.kv(facts, rows.filter((row) => row[1]));
        }
        if (Array.isArray(result.details.fields)) tree.appendChild(tlvTree(result.details.fields));
      }
      if (!tree.firstChild) tree.appendChild(el('p', { class: 'a-muted' }, t('pix.decode.empty')));
      renderCrc(play);
    }

    function renderCrc(play) {
      clear(ui.crc);
      const crc = state.decoded && state.decoded.details && state.decoded.details.crc;
      if (!crc || !Array.isArray(crc.steps) || !crc.steps.length) { emptyState(ui.crc, t('explain.empty.title'), t('crc.empty')); return; }
      const holder = el('div', { class: 'pg-crc-stage' });
      ui.crc.appendChild(holder);
      stepper = mountExplainer(holder, explainCrc(state.decoded), { skip: true, end: true });
      const table = el('div');
      const details = Aurora.details(null, { summary: t('crc.all'), content: table });
      details.classList.add('pg-details');
      ui.crc.appendChild(details);
      Aurora.table(table, {
        dense: true, pageSize: 12,
        columns: [{ key: 'n', label: t('crc.col.n'), align: 'right' }, { key: 'char', label: t('crc.byte'), mono: true }, { key: 'index', label: t('crc.index').split(' = ')[0], mono: true },
          { key: 'table', label: t('crc.table'), mono: true }, { key: 'crc', label: t('crc.reg').split(' = ')[0], mono: true }],
        rows: crc.steps.map((step, i) => ({ n: i + 1, char: `${printable(step.byte)}  0x${hex(step.byte)}`, index: hex(step.index), table: `0x${hex(step.table, 4)}`, crc: hex(step.crc, 4) })),
        sort: { key: 'n', dir: 'asc' },
      });
      if (play) stepper.autoplay(); else stepper.show();
    }

    async function decodeNow(play) {
      const text = state.text;
      if (!text.trim()) { state.decoded = null; state.decodeError = null; state.busy = false; renderDecoded(false); return; }
      state.busy = true;
      ui.decoded.classList.add('a-refreshing');
      ui.facts.classList.add('a-refreshing');
      try {
        const outcome = await runDecode((signal) => api.post('/api/v1/pix/decode', { payload: text, explain: true }, signal));
        if (!outcome) return;
        state.decoded = outcome.value; state.decodeError = null;
      } catch (error) {
        state.decoded = null; state.decodeError = error;
        if (error.status === 429) Aurora.toast(describeApiError(error), { kind: 'warn' });
      }
      state.busy = false;
      renderDecoded(play);
    }
    const decodeSoon = Aurora.debounce(() => decodeNow(true), 300);

    function setText(text, immediate) {
      state.text = text;
      if (ui.textarea) ui.textarea.value = text;
      if (immediate) decodeNow(true); else decodeSoon();
    }

    function build() {
      if (stepper) stepper.destroy();
      stepper = null;
      clear(root);
      const answer = resultCard();
      ui = { inputs: {}, errors: {}, built: el('div', { class: 'pg-built', 'aria-live': 'polite' }), decoded: answer.verdict, facts: answer.facts, tree: el('div', { class: 'pg-tree' }), crc: el('div', { class: 'pg-crc-slot' }) };

      const field = (name, label, control, hint) => {
        const id = Aurora.uid(`pix-${name}`);
        control.id = id;
        control.addEventListener('input', () => { state.form[name] = control.value; buildSoon(); });
        control.addEventListener('change', () => { state.form[name] = control.value; buildSoon(); });
        ui.inputs[name] = control;
        ui.errors[name] = el('span', { class: 'a-field__error', role: 'alert' });
        return el('div', { class: 'a-field' }, el('label', { for: id }, label), control, ui.errors[name], hint ? el('span', { class: 'a-field__hint' }, hint) : null);
      };
      const text = (name, label, placeholder, extra) => field(name, label, el('input', Object.assign({ class: 'a-input', type: 'text', value: state.form[name], placeholder: placeholder || null, autocomplete: 'off', spellcheck: 'false' }, extra || {})));
      const keyTypes = [['', t('pix.keytype.auto')]].concat(['cpf', 'cnpj', 'phone', 'email', 'evp'].map((type) => [type, t(`pix.keytype.${type}`)]));
      const keyTypeSelect = el('select', { class: 'a-select' }, keyTypes.map(([value, label]) => el('option', { value, selected: value === state.form.key_type }, label)));

      const builderCard = card({ title: t('pix.build.title'), sub: t('pix.build.sub') });
      builderCard.body.append(
        el('div', { class: 'pg-form' },
          text('key', t('pix.field.key'), t('pix.ph.key'), { maxlength: 100 }), field('key_type', t('pix.field.keytype'), keyTypeSelect),
          text('amount', t('pix.field.amount'), '12.50', { inputmode: 'decimal', maxlength: 14 }),
          text('name', t('pix.field.name'), null, { maxlength: 60 }), text('city', t('pix.field.city'), null, { maxlength: 40 }),
          text('txid', t('pix.field.txid'), 'PED123', { maxlength: 40 }), text('message', t('pix.field.message'), null, { maxlength: 80 })),
        ui.built);

      const codeId = Aurora.uid('pix-code');
      const hintId = `${codeId}-hint`;
      const textarea = el('textarea', { class: 'a-composer__input pg-composer__code', id: codeId, rows: 4, spellcheck: 'false', autocomplete: 'off', autocapitalize: 'off', maxlength: 2048, 'aria-describedby': hintId, oninput: (event) => { state.linked = false; setText(event.target.value, false); } });
      textarea.value = state.text;
      ui.textarea = textarea;
      const decoder = composer({
        label: t('pix.decode.field'), input: textarea, hint: t('pix.decode.sub'), hintId,
        chips: [
          chipButton(t('pix.decode.example'), () => { state.linked = false; setText(BCB_EXAMPLE, true); }),
          chipButton(t('pix.decode.tamper'), () => { state.linked = false; setText(tamper(state.text, state.decoded), true); }),
          chipButton(t('validate.clear'), () => { state.linked = false; setText('', true); textarea.focus(); }),
        ],
      });

      const treeCard = card({ title: t('pix.tree.title') });
      treeCard.body.appendChild(ui.tree);

      const crcCard = card({ title: t('crc.title'), sub: t('explain.sub.crc') });
      crcCard.body.appendChild(ui.crc);

      root.append(el('div', { class: 'a-span-5 pg-column' }, decoder, answer.el, builderCard.el), el('div', { class: 'a-span-7 pg-column' }, treeCard.el, crcCard.el));
      built = true;
      renderBuilt(); renderDecoded(false);
    }

    return {
      el: root,
      activate() {
        if (built) return;
        build();
        if (apiDown()) {
          state.buildError = unreachable(); state.decodeError = state.buildError;
          renderBuilt(); renderDecoded(false);
          return;
        }
        buildNow();
      },
      deactivate() { if (stepper) stepper.stop(); },
      rebuild() { if (built) build(); },
      generate() { if (built) { state.linked = true; buildNow(); } },
      replay() { if (stepper) stepper.autoplay(); },
      useExample() { if (built) { state.linked = false; setText(BCB_EXAMPLE, true); } },
    };
  }

  /* ════════════════════════════ 9. fake people tab ════════════════════════════ */
  function createFakeTab() {
    const state = { count: 3, seed: '', people: null, seedUsed: null, selected: 0, error: null, explain: null, explainError: null };
    const root = el('div', { class: 'a-grid pg-tab pg-tab--explain' });
    const runGenerate = latest();
    const runExplain = latest();
    let stepper = null;
    let built = false;
    let ui = {};

    function renderExplain(play) {
      if (stepper) stepper.destroy();
      stepper = null;
      const box = clear(ui.explain);
      const person = state.people && state.people[state.selected];
      const result = state.explain;
      if (!person || !result || !result.details || !Array.isArray(result.details.steps)) {
        if (state.explainError) box.appendChild(notice(describeApiError(state.explainError), 'warn')); else emptyState(box, t('explain.empty.title'), t('fake.empty'));
        return;
      }
      const holder = el('div', { class: 'pg-crc-stage' });
      box.appendChild(holder);
      stepper = mountExplainer(holder, explainMod11(result.details.steps));
      if (result.details.ufs) {
        box.appendChild(el('p', { class: 'pg-note pg-note--spaced' }, icon('info', { size: 14 }),
          t('fake.region', { digit: result.details.region_digit, ufs: result.details.ufs.join(', '), uf: person.address.uf })));
      }
      if (play) stepper.autoplay(); else stepper.show();
    }

    async function select(index, play) {
      state.selected = index;
      renderPeople();
      const person = state.people[index];
      try {
        const outcome = await runExplain((signal) => api.get('/api/v1/cpf/validate', { cpf: person.cpf, explain: 'true' }, signal));
        if (!outcome) return;
        state.explain = outcome.value; state.explainError = null;
      } catch (error) { state.explain = null; state.explainError = error; }
      ui.cardTitle.textContent = t('fake.selected', { name: person.name });
      renderExplain(play);
    }

    function renderPeople() {
      const box = clear(ui.people);
      if (state.error) { box.appendChild(notice(describeApiError(state.error), 'warn')); return; }
      if (!state.people) { box.appendChild(el('p', { class: 'a-muted' }, t('fake.empty'))); return; }
      const inline = (value, label) => el('span', { class: 'pg-inline' }, mono(value), copyButton(value, `${t('gen.copy')}: ${label}`, true));
      const list = el('ul', { class: 'pg-people' });
      state.people.forEach((person, index) => {
        const address = person.address;
        const street = [address.street, address.number, address.complement].filter(Boolean).join(', ');
        const selected = index === state.selected;
        list.appendChild(el('li', { class: `pg-person${selected ? ' is-selected' : ''}` },
          el('div', { class: 'pg-person__head' }, el('strong', person.name), el('span', { class: 'a-tag' }, t(`fake.gender.${person.gender}`)),
            el('span', { class: 'a-spacer' }),
            el('button', { class: 'a-btn a-btn--ghost a-btn--sm', type: 'button', 'aria-pressed': String(selected), onclick: () => select(index, true) }, icon('sparkle', { size: 14 }), t('fake.explain')),
            iconButton('code', `${t('fake.json')}: ${person.name}`, () => copyText(JSON.stringify(person, null, 2)))),
          Aurora.kv(null, [
            [t('fake.cpf'), inline(person.cpf, 'CPF')], [t('fake.phone'), inline(person.phone, t('fake.phone'))], [t('fake.email'), inline(person.email, t('fake.email'))],
            [t('fake.born'), mono(person.birthdate)], [t('fake.address'), `${street} · ${address.neighborhood}, ${address.city}/${address.uf} · ${address.cep}`],
          ])));
      });
      box.appendChild(list);
      box.appendChild(el('p', { class: 'a-faint pg-results__foot' }, t('gen.seedused', { seed: state.seedUsed })));
    }

    async function generateNow() {
      ui.generate.disabled = true;
      try {
        const outcome = await runGenerate((signal) => api.get('/api/v1/fake/person', { count: state.count, seed: state.seed }, signal));
        if (!outcome) return;
        state.people = outcome.value.items; state.seedUsed = outcome.value.seed; state.error = null; state.selected = 0;
      } catch (error) {
        state.error = error; state.people = null;
        if (error.status === 429) Aurora.toast(describeApiError(error), { kind: 'warn' });
      }
      ui.generate.disabled = false;
      renderPeople();
      if (state.people) select(0, true); else renderExplain(false);
    }

    function build() {
      if (stepper) stepper.destroy();
      stepper = null;
      clear(root);
      const uid = Aurora.uid('fake');
      ui = { people: el('div', { class: 'pg-people-slot' }), explain: el('div', { class: 'pg-explain-slot' }) };
      ui.generate = el('button', { class: 'a-btn a-btn--primary', type: 'button', onclick: generateNow }, icon('bolt', { size: 16 }), t('gen.button'));
      const controls = card({ title: t('fake.title'), sub: t('fake.sub'), className: 'a-span-12' });
      controls.body.append(
        notice(t('fake.notice.text'), 'warn', t('fake.notice.title')),
        el('div', { class: 'pg-options pg-options--inline' },
          labelled(`${uid}-count`, t('gen.count'), numberControl(`${uid}-count`, state.count, 1, 10, (value) => { state.count = value; })),
          labelled(`${uid}-seed`, t('gen.seed'), numberControl(`${uid}-seed`, state.seed, 0, 4294967295, (value) => { state.seed = value; }, t('gen.seed.hint'))),
          el('div', { class: 'pg-actions pg-actions--end' }, ui.generate)));
      const people = card({ title: t('result.title'), className: 'a-span-6' });
      people.body.appendChild(ui.people);
      const explain = card({ title: t('explain.title'), sub: t('explain.sub.mod11'), className: 'a-span-6 pg-sticky' });
      ui.cardTitle = explain.el.querySelector('.a-card__title');
      explain.body.appendChild(ui.explain);
      root.append(controls.el, people.el, explain.el);
      built = true;
      renderPeople(); renderExplain(false);
      if (state.people) ui.cardTitle.textContent = t('fake.selected', { name: state.people[state.selected].name });
    }

    return {
      el: root,
      activate() {
        if (built) return;
        build();
        if (apiDown()) { state.error = unreachable(); renderPeople(); renderExplain(false); return; }
        generateNow();
      },
      deactivate() { if (stepper) stepper.stop(); },
      rebuild() { if (built) build(); },
      generate() { if (built) generateNow(); },
      replay() { if (stepper) stepper.autoplay(); },
      useExample() { if (built) generateNow(); },
    };
  }

  /* ════════════════════════════ 10. shell ════════════════════════════
   * Aurora.shell builds the navigation rail, the top bar (breadcrumbs, search, live state, language, theme), the tool
   * pills of the sub bar and the status bar. The tools are routes (#cpf, #pix, ...): the pills are links and the hash
   * is the only state. Every label the shell shows goes through t(), so a language switch updates all of them. */
  const BRAND = 'Kit Brasil';
  const TAB_IDS = ['cpf', 'cnpj', 'pix', 'card', 'plate', 'phone', 'cep', 'fake'];
  const TAB_ICONS = { cpf: 'id-card', cnpj: 'building', pix: 'qr', card: 'credit-card', plate: 'car', phone: 'phone', cep: 'map-pin', fake: 'users' };
  const ALGO_ICONS = { cpf: 'hash', cnpj: 'hash', pix: 'hash', card: 'hash', plate: 'refresh', phone: 'list', cep: 'flag', fake: 'sparkle' };
  const views = {};
  const panels = {};
  const hero = {};
  let shell = null;
  let langSwitch = null;
  let active = 'cpf';

  function makeView(id) {
    if (id === 'pix') return createPixTab();
    if (id === 'fake') return createFakeTab();
    return createDocTab(id);
  }

  const routeId = () => {
    const id = window.location.hash.slice(1);
    return TAB_IDS.includes(id) ? id : 'cpf';
  };

  /** The sub bar's small pill: the algorithm behind the current tool. */
  function algoPill(id) {
    const text = t(`algo.${id}`);
    return el('span', { class: 'a-pill pg-algo', title: text }, icon(ALGO_ICONS[id], { size: 14 }), el('span', { class: 'a-pill__label' }, text));
  }

  const tabsOptions = () => ({
    ariaLabel: t('tabs.label'), active,
    items: TAB_IDS.map((id) => ({ id, label: t(`tab.${id}`), icon: TAB_ICONS[id], href: `#${id}` })),
  });

  /** On narrow screens the pills scroll sideways: keep the current one in view. */
  function revealActivePill() {
    const current = shell.tabs && shell.tabs.el.querySelector('.is-active');
    if (current) current.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }

  /** Shows one tool (built on first use) and keeps the crumbs, the pills and the algorithm pill in step with it. */
  function show(id) {
    if (!views[id]) return;
    if (active !== id) views[active].deactivate();
    active = id;
    TAB_IDS.forEach((tool) => { panels[tool].hidden = tool !== id; });
    shell.tabs.select(id, true);
    shell.setCrumbs([BRAND, t(`tab.${id}`)]);
    shell.setSubbarEnd([algoPill(id)]);
    views[id].activate();
    revealActivePill();
  }

  /** Navigates through the hash, so the back button and shared links work; the hashchange listener does the rest. */
  function go(id) {
    if (window.location.hash === `#${id}`) show(id); else window.location.hash = id;
  }

  /** Gives Aurora's built-in labels (palette, tables, theme toggle, landmarks) the current language. */
  function localiseKit() {
    const strings = {};
    Object.keys(MESSAGES.pt).filter((key) => key.startsWith('aurora.')).forEach((key) => { strings[key.slice('aurora.'.length)] = t(key); });
    Aurora.setStrings(strings);
    Aurora.theme.sync();
  }

  function statusLine() {
    return {
      start: [liveState.version ? t('status.version', { version: `v${liveState.version}` }) : 'brkit', t('status.license')],
      end: [t('status.local')],
    };
  }

  function renderLangSwitch() {
    langSwitch.setAttribute('aria-label', t('top.lang'));
    langSwitch.querySelectorAll('button').forEach((button) => {
      const on = button.dataset.lang === lang.current;
      button.classList.toggle('is-active', on);
      button.setAttribute('aria-pressed', String(on));
    });
  }

  /** Everything the shell shows that depends on the language or on the current tool. */
  function renderChrome() {
    const name = (node, text) => { node.setAttribute('aria-label', text); if (node.hasAttribute('data-tip')) node.setAttribute('data-tip', text); };
    name(shell.items.playground, t('rail.playground'));
    name(shell.items.api, t('rail.api'));
    name(shell.items.palette, t('rail.palette'));
    shell.rail.setAttribute('aria-label', t('aurora.shell.rail'));
    shell.topbar.querySelector('.a-crumbs').setAttribute('aria-label', t('aurora.shell.here'));
    const search = shell.topbar.querySelector('.a-search');
    search.setAttribute('aria-label', t('aurora.shell.search'));
    search.querySelector('span').textContent = t('aurora.shell.search');
    document.querySelector('.a-skip').textContent = t('aurora.shell.skip');
    renderLangSwitch();
    shell.setTabs(tabsOptions());
    revealActivePill();
    shell.setCrumbs([BRAND, t(`tab.${active}`)]);
    shell.setSubbarEnd([algoPill(active)]);
    shell.setStatus(statusLine());
    setLive(liveState.state);
  }

  function buildHero(parent) {
    hero.greet = el('p', { class: 'a-greet' });
    hero.lede = el('p', { class: 'a-lede' });
    hero.tags = ['api', 'offline', 'deps'].map(() => el('span', { class: 'a-tag' }));
    parent.appendChild(el('section', { class: 'a-hero pg-hero', 'aria-labelledby': 'intro-title' },
      hero.greet, el('h1', { class: 'a-headline', id: 'intro-title' }, BRAND), hero.lede, el('div', { class: 'a-row' }, hero.tags)));
  }

  function renderHero() {
    hero.greet.textContent = t('app.eyebrow');
    hero.lede.textContent = t('app.lead');
    ['api', 'offline', 'deps'].forEach((key, i) => { hero.tags[i].textContent = t(`app.chip.${key}`); });
  }

  function syncDocument() {
    document.documentElement.lang = lang.current === 'pt' ? 'pt-BR' : 'en';
    document.title = t('app.title');
  }

  function applyLanguage() {
    syncDocument();
    localiseKit();
    renderChrome();
    renderHero();
    Object.keys(views).forEach((id) => views[id].rebuild());
    registerCommands();
  }

  function setLanguage(next) {
    if (next === lang.current || !MESSAGES[next]) return;
    lang.current = next;
    try { window.localStorage.setItem(LANG_KEY, next); } catch (error) { /* storage unavailable */ }
    applyLanguage();
  }

  /* — command palette (Ctrl/Cmd+K) — */
  function registerCommands() {
    const nav = TAB_IDS.map((id) => ({ id: `go-${id}`, label: t('cmd.goto', { tab: t(`tab.${id}`) }), group: t('cmd.group.nav'), keywords: `${id} ${t(`tab.${id}`)}`, run: () => go(id) }));
    const actions = [
      { id: 'generate', label: t('cmd.generate'), group: t('cmd.group.actions'), keywords: 'generate gerar', run: () => views[active].generate() },
      { id: 'example', label: t('cmd.example'), group: t('cmd.group.actions'), keywords: 'example exemplo', run: () => views[active].useExample() },
      { id: 'replay', label: t('cmd.replay'), group: t('cmd.group.actions'), keywords: 'animation animação replay', run: () => views[active].replay() },
      { id: 'theme', label: t('cmd.theme'), group: t('cmd.group.prefs'), keywords: 'theme tema dark light escuro claro', run: () => Aurora.theme.toggle() },
      { id: 'lang', label: t('cmd.lang', { lang: t('cmd.lang.target') }), group: t('cmd.group.prefs'), keywords: 'language idioma english português', run: () => setLanguage(lang.current === 'pt' ? 'en' : 'pt') },
      { id: 'openapi', label: t('cmd.openapi'), group: t('cmd.group.prefs'), keywords: 'openapi api swagger', run: () => window.open('/api/v1/openapi.json', '_blank', 'noopener') },
    ];
    Aurora.cmdk.register(nav.concat(actions));
  }

  async function boot() {
    syncDocument();
    localiseKit();
    active = routeId();
    liveState.ui = Aurora.live(null, { label: t('live.connecting') });
    liveState.ui.el.classList.add('pg-live');
    langSwitch = el('div', { class: 'a-seg pg-lang', role: 'group' },
      ['pt', 'en'].map((code) => el('button', { class: 'a-seg__item', type: 'button', lang: code === 'pt' ? 'pt-BR' : 'en', 'data-lang': code, onclick: () => setLanguage(code) }, code.toUpperCase())));

    // The shell appears at once; the tools follow when the API has answered (the option lists come from it).
    shell = Aurora.shell({
      brand: { name: BRAND, href: '#cpf', mark: 'id-card' },
      rail: [
        [{ id: 'playground', label: t('rail.playground'), icon: 'home', href: '#cpf', active: true },
          { id: 'api', label: t('rail.api'), icon: 'code', href: '/api/v1/openapi.json', external: true }],
        'spacer',
        [{ id: 'palette', label: t('rail.palette'), icon: 'command', cmdk: true }],
      ],
      crumbs: [BRAND, t(`tab.${active}`)],
      search: { label: t('aurora.shell.search') },
      actions: [liveState.ui.el, langSwitch],
      tabs: tabsOptions(),
      subbarEnd: [algoPill(active)],
      status: statusLine(),
    });
    buildHero(shell.container);
    const host = el('div', { class: 'pg-panels' });
    shell.container.appendChild(host);
    const loading = Aurora.skeleton(host, { lines: 3, height: '18px' });
    renderHero();
    renderLangSwitch();

    // Opened from disk there is no server to ask; with a server, one probe tells the tools whether to call the API.
    const health = window.location.protocol === 'file:' ? null : await api.get('/healthz').catch(() => null);
    liveState.version = health ? health.version : '';
    setLive(health ? 'live' : 'offline');
    if (health) await loadCatalog();
    shell.setStatus(statusLine());

    loading.remove();
    TAB_IDS.forEach((id) => {
      views[id] = makeView(id);
      panels[id] = el('div', { class: 'pg-panel', id: `panel-${id}`, hidden: true }, views[id].el);
      host.appendChild(panels[id]);
    });
    document.addEventListener('visibilitychange', () => { if (document.hidden && views[active]) views[active].deactivate(); });
    window.addEventListener('hashchange', () => { if (routeId() !== active) show(routeId()); });
    registerCommands();
    show(routeId()); // the hash may have changed while the first probe was in flight
  }

  boot();
})();
