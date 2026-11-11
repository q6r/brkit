# frozen_string_literal: true

module Brkit
  module Fake
    # Word lists for the fake-person generator. Everything here is common, generic vocabulary:
    # no real person, street address or company is represented.
    # @api private
    module Data
      FEMALE_NAMES = %w[
        Maria Ana Francisca Antônia Adriana Juliana Márcia Fernanda Patrícia Aline Sandra Camila Amanda Bruna
        Jéssica Letícia Júlia Luciana Vanessa Mariana Gabriela Beatriz Larissa Rafaela Carolina Daniela Renata
        Priscila Natália Cláudia Simone Tatiane Eduarda Luana Isabela Débora Raquel Viviane Sônia Helena
      ].freeze

      MALE_NAMES = %w[
        João José Antônio Francisco Carlos Paulo Pedro Lucas Luiz Marcos Gabriel Rafael Daniel Marcelo Bruno
        Eduardo Felipe Rodrigo Fernando Gustavo Ricardo Leonardo André Thiago Diego Mateus Vinícius Sérgio
        Roberto Alexandre Henrique Renato Caio Fábio Márcio Leandro Murilo Otávio Davi Heitor
      ].freeze

      SURNAMES = %w[
        Silva Santos Oliveira Souza Rodrigues Ferreira Alves Pereira Lima Gomes Costa Ribeiro Martins Carvalho
        Almeida Lopes Soares Fernandes Vieira Barbosa Rocha Dias Nascimento Andrade Moreira Nunes Marques Machado
        Mendes Freitas Cardoso Ramos Gonçalves Santana Teixeira Araújo Pinto Correia Monteiro Moura Cavalcanti
        Azevedo Duarte Campos Borges Batista Pires Medeiros Melo Barros
      ].freeze

      EMAIL_DOMAINS = %w[example.com example.org example.net].freeze

      STREET_TYPES = %w[Rua Avenida Travessa Alameda Praça].freeze

      STREET_NAMES = [
        "das Flores", "Sete de Setembro", "XV de Novembro", "Presidente Vargas", "Getúlio Vargas", "Tiradentes",
        "Brasil", "da Independência", "da Liberdade", "Santos Dumont", "Marechal Deodoro", "São João",
        "Duque de Caxias", "Rio Branco", "das Palmeiras", "Dom Pedro II", "Castro Alves", "Machado de Assis",
        "Quinze de Novembro", "dos Andradas", "Bandeirantes", "das Acácias"
      ].freeze

      NEIGHBORHOODS = [
        "Centro", "Jardim América", "Vila Nova", "Bela Vista", "Boa Vista", "Santa Cruz", "São José", "Industrial",
        "Jardim das Flores", "Alto da Boa Vista", "Liberdade", "Cidade Nova", "Parque das Nações", "Vila Rica",
        "Jardim Botânico", "Santo Antônio"
      ].freeze

      COMPLEMENTS = ["Apto 12", "Apto 304", "Casa 2", "Sala 301", "Bloco B", "Fundos", "Loja 5"].freeze

      # name, UF, area code (DDD)
      CITIES = [
        ["São Paulo", "SP", "11"], ["Guarulhos", "SP", "11"], ["Campinas", "SP", "19"],
        ["São José dos Campos", "SP", "12"], ["Santos", "SP", "13"], ["Ribeirão Preto", "SP", "16"],
        ["Sorocaba", "SP", "15"], ["Bauru", "SP", "14"], ["São José do Rio Preto", "SP", "17"],
        ["Presidente Prudente", "SP", "18"],
        ["Rio de Janeiro", "RJ", "21"], ["Niterói", "RJ", "21"], ["Campos dos Goytacazes", "RJ", "22"],
        ["Volta Redonda", "RJ", "24"],
        ["Vitória", "ES", "27"], ["Vila Velha", "ES", "27"], ["Cachoeiro de Itapemirim", "ES", "28"],
        ["Belo Horizonte", "MG", "31"], ["Contagem", "MG", "31"], ["Juiz de Fora", "MG", "32"],
        ["Governador Valadares", "MG", "33"], ["Uberlândia", "MG", "34"], ["Poços de Caldas", "MG", "35"],
        ["Montes Claros", "MG", "38"],
        ["Curitiba", "PR", "41"], ["Ponta Grossa", "PR", "42"], ["Londrina", "PR", "43"], ["Maringá", "PR", "44"],
        ["Cascavel", "PR", "45"], ["Foz do Iguaçu", "PR", "45"], ["Pato Branco", "PR", "46"],
        ["Joinville", "SC", "47"], ["Blumenau", "SC", "47"], ["Florianópolis", "SC", "48"], ["Chapecó", "SC", "49"],
        ["Porto Alegre", "RS", "51"], ["Pelotas", "RS", "53"], ["Caxias do Sul", "RS", "54"],
        ["Santa Maria", "RS", "55"],
        ["Brasília", "DF", "61"], ["Goiânia", "GO", "62"], ["Anápolis", "GO", "62"], ["Palmas", "TO", "63"],
        ["Rio Verde", "GO", "64"], ["Cuiabá", "MT", "65"], ["Rondonópolis", "MT", "66"],
        ["Campo Grande", "MS", "67"], ["Dourados", "MS", "67"], ["Rio Branco", "AC", "68"],
        ["Porto Velho", "RO", "69"],
        ["Salvador", "BA", "71"], ["Ilhéus", "BA", "73"], ["Porto Seguro", "BA", "73"],
        ["Feira de Santana", "BA", "75"], ["Vitória da Conquista", "BA", "77"], ["Aracaju", "SE", "79"],
        ["Recife", "PE", "81"], ["Caruaru", "PE", "81"], ["Petrolina", "PE", "87"], ["Maceió", "AL", "82"],
        ["Arapiraca", "AL", "82"], ["João Pessoa", "PB", "83"], ["Campina Grande", "PB", "83"],
        ["Natal", "RN", "84"], ["Mossoró", "RN", "84"],
        ["Fortaleza", "CE", "85"], ["Juazeiro do Norte", "CE", "88"], ["Teresina", "PI", "86"],
        ["Parnaíba", "PI", "86"], ["Picos", "PI", "89"],
        ["Belém", "PA", "91"], ["Santarém", "PA", "93"], ["Marabá", "PA", "94"], ["Manaus", "AM", "92"],
        ["Parintins", "AM", "92"], ["Tefé", "AM", "97"], ["Boa Vista", "RR", "95"], ["Macapá", "AP", "96"],
        ["São Luís", "MA", "98"], ["Imperatriz", "MA", "99"]
      ].freeze
    end
  end
end
