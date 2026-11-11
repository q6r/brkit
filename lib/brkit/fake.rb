# frozen_string_literal: true

require "date"

require_relative "cep"
require_relative "cpf"
require_relative "phone"
require_relative "rng"
require_relative "text"
require_relative "fake/data"

module Brkit
  # Seeded generator of fictitious Brazilian people for tests, demos and seed data.
  #
  # Everything is synthetic: names are random combinations of common given names and surnames, the CPF
  # passes the checksum but belongs to nobody in particular, e-mail addresses use the reserved
  # +example.com+/+.org+/+.net+ domains, and addresses are made-up street names with a CEP whose prefix
  # lies in the person's state. The phone's area code and the CPF's fiscal region match the person's
  # state, so the pieces look consistent.
  #
  # Output is fully determined by the random source: the same +seed:+ always yields the same people,
  # and +people(3, seed: 42).first == person(seed: 42)+. The order in which values are drawn is part of
  # the contract (a change would alter every seeded result), so it only changes in major versions.
  #
  # Birthdates are computed from +reference_date+ (default {DEFAULT_REFERENCE_DATE}), not from today's
  # date, so seeded output does not drift as time passes.
  module Fake
    # Fixed anchor for ages, keeping seeded output stable across days.
    DEFAULT_REFERENCE_DATE = Date.new(2026, 1, 1)
    MIN_AGE_YEARS = 18
    MAX_AGE_YEARS = 80

    # One fictitious person.
    #
    # @!attribute [r] name
    #   @return [String] full name, 2 surnames and sometimes a middle name
    # @!attribute [r] gender
    #   @return [String] +"F"+ or +"M"+
    # @!attribute [r] cpf
    #   @return [String] formatted CPF
    # @!attribute [r] email
    #   @return [String] address on a reserved example domain
    # @!attribute [r] phone
    #   @return [String] formatted mobile number, area code of the person's city
    # @!attribute [r] phone_e164
    #   @return [String] the same number in E.164
    # @!attribute [r] birthdate
    #   @return [Date] between 18 and 80 years before the reference date
    # @!attribute [r] address
    #   @return [Hash{Symbol=>String, nil}] +street+, +number+, +complement+, +neighborhood+, +city+, +uf+, +cep+
    Person = Struct.new(:name, :gender, :cpf, :email, :phone, :phone_e164, :birthdate, :address, keyword_init: true) do
      # @return [Hash{Symbol=>Object}] JSON-friendly form (+birthdate+ as ISO 8601 text)
      def to_h
        { name: name, gender: gender, cpf: cpf, email: email, phone: phone, phone_e164: phone_e164,
          birthdate: birthdate.iso8601, address: address }
      end
    end

    class << self
      # Generates one person.
      #
      # @param rng [#rand, nil] random source (see {Rng})
      # @param seed [Integer, nil] seed for a reproducible result
      # @param reference_date [Date] the date ages are measured from
      # @return [Person]
      def person(rng: nil, seed: nil, reference_date: DEFAULT_REFERENCE_DATE)
        build(Rng.resolve(rng: rng, seed: seed), reference_date)
      end

      # Generates several people from one random stream.
      #
      # @param count [Integer] how many (0 or more)
      # @return [Array<Person>]
      # @raise [InvalidInputError] when +count+ is negative or not an Integer
      def people(count, rng: nil, seed: nil, reference_date: DEFAULT_REFERENCE_DATE)
        unless count.is_a?(Integer) && count >= 0
          raise InvalidInputError.for(:invalid_count, "count must be a non-negative integer", field: "count")
        end

        random = Rng.resolve(rng: rng, seed: seed)
        Array.new(count) { build(random, reference_date) }
      end

      private

      def build(random, reference_date)
        gender = Rng.pick(random, %w[F M])
        name = full_name(random, gender)
        city, uf, ddd = Rng.pick(random, Data::CITIES)
        phone = Phone.generate(ddd: ddd, rng: random)
        Person.new(
          name: name, gender: gender, cpf: CPF.generate(uf: uf, formatted: true, rng: random),
          email: email_for(random, name), phone: Phone.format(phone), phone_e164: phone,
          birthdate: birthdate(random, reference_date), address: address(random, city, uf)
        )
      end

      def full_name(random, gender)
        givens = gender == "F" ? Data::FEMALE_NAMES : Data::MALE_NAMES
        parts = [Rng.pick(random, givens)]
        parts << Rng.pick(random, givens - parts) if Rng.chance?(random, 25)
        first_surname = Rng.pick(random, Data::SURNAMES)
        parts << first_surname << Rng.pick(random, Data::SURNAMES - [first_surname])
        parts.join(" ")
      end

      def email_for(random, name)
        words = name.split
        local = [words.first, words.last].map { |word| Text.fold(word).downcase.gsub(/[^a-z]/, "") }.join(".")
        "#{local}#{random.rand(10..99)}@#{Rng.pick(random, Data::EMAIL_DOMAINS)}"
      end

      def birthdate(random, reference_date)
        days = random.rand((MIN_AGE_YEARS * 365)..(MAX_AGE_YEARS * 365))
        reference_date - days
      end

      def address(random, city, uf)
        {
          street: "#{Rng.pick(random, Data::STREET_TYPES)} #{Rng.pick(random, Data::STREET_NAMES)}",
          number: random.rand(1..9999).to_s,
          complement: Rng.chance?(random, 35) ? Rng.pick(random, Data::COMPLEMENTS) : nil,
          neighborhood: Rng.pick(random, Data::NEIGHBORHOODS),
          city: city, uf: uf, cep: CEP.generate(uf: uf, formatted: true, rng: random)
        }
      end
    end
  end
end
