# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  class FakeTest < Minitest::Test
    # Part of the reproducibility contract: seed 42 must keep producing this person.
    GOLDEN = {
      name: "Natália Fernanda Rocha Moura", gender: "F", cpf: "417.514.092-10", email: "natalia.moura98@example.com",
      phone: "(92) 98743-7725", phone_e164: "+5592987437725", birthdate: "1984-04-15",
      address: { street: "Travessa Santos Dumont", number: "2048", complement: nil, neighborhood: "Cidade Nova",
                 city: "Parintins", uf: "AM", cep: "69882-189" }
    }.freeze

    def people
      @people ||= Fake.people(150, seed: 2026)
    end

    def test_golden_person_for_seed_42
      assert_equal GOLDEN, Fake.person(seed: 42).to_h
    end

    def test_same_seed_same_people
      assert_equal Fake.people(5, seed: 7).map(&:to_h), Fake.people(5, seed: 7).map(&:to_h)
      assert_equal Fake.person(seed: 1).to_h, Fake.person(seed: 1).to_h
      refute_equal Fake.person(seed: 1).to_h, Fake.person(seed: 2).to_h
    end

    def test_a_person_is_the_first_of_a_larger_batch
      assert_equal Fake.people(3, seed: 42).first, Fake.person(seed: 42)
      assert_equal Fake.people(3, seed: 42).first(2), Fake.people(2, seed: 42)
    end

    def test_accepts_an_rng
      assert_equal Fake.person(seed: 9), Fake.person(rng: Random.new(9))
      random = Random.new(9)
      first = Fake.person(rng: random)
      second = Fake.person(rng: random)
      refute_equal first, second
      assert_equal [first, second], Fake.people(2, seed: 9)
    end

    def test_count_validation
      assert_equal [], Fake.people(0, seed: 1)
      assert_equal 1, Fake.people(1, seed: 1).length
      ["3", nil, -1, 1.5, [3]].each do |count|
        error = assert_raises(InvalidInputError, count.inspect) { Fake.people(count, seed: 1) }
        assert_equal [:invalid_count], error.issues.map(&:code)
      end
    end

    def test_conflicting_randomness_is_rejected
      assert_raises(InvalidInputError) { Fake.person(rng: Random.new(1), seed: 1) }
    end

    def test_every_cpf_is_valid_and_matches_the_state
      people.each do |person|
        result = CPF.validate(person.cpf)
        assert_valid result, person.cpf
        assert_includes result.details[:ufs], person.address[:uf], "#{person.cpf} vs #{person.address[:uf]}"
      end
    end

    def test_every_phone_is_a_mobile_number_in_the_city_area_code
      people.each do |person|
        result = Phone.validate(person.phone)
        assert_valid result, person.phone
        assert_equal "mobile", result.details[:type]
        assert_equal person.phone_e164, result.normalized
        assert_equal person.address[:uf], result.details[:uf]
        _name, _uf, ddd = Fake::Data::CITIES.find { |name, uf, _| name == person.address[:city] && uf == person.address[:uf] }
        assert_equal ddd, result.details[:area_code]
      end
    end

    def test_every_cep_is_valid_and_inside_the_state
      people.each do |person|
        cep = person.address[:cep]
        assert_valid CEP.validate(cep), cep
        assert_equal person.address[:uf], CEP.uf_for(cep), "#{cep} for #{person.address[:city]}"
      end
    end

    def test_emails_use_reserved_domains_and_plain_ascii
      people.each do |person|
        assert_match(/\A[a-z]+\.[a-z]+\d{2}@example\.(com|org|net)\z/, person.email, person.name)
        assert_predicate person.email, :ascii_only?
      end
    end

    def test_names
      givens = Fake::Data::FEMALE_NAMES + Fake::Data::MALE_NAMES
      people.each do |person|
        parts = person.name.split
        assert_includes 3..4, parts.length, person.name
        assert_includes givens, parts.first
        assert_equal parts.uniq, parts, "no repeated word in #{person.name}"
        refute_match(/\d/, person.name)
        assert_equal(person.gender == "F", Fake::Data::FEMALE_NAMES.include?(parts.first), person.name)
      end
    end

    def test_birthdates_are_between_18_and_80_years_before_the_reference_date
      reference = Fake::DEFAULT_REFERENCE_DATE
      people.each do |person|
        assert_kind_of Date, person.birthdate
        assert_operator person.birthdate, :<=, reference - (18 * 365)
        assert_operator person.birthdate, :>=, reference - (80 * 365)
      end
    end

    def test_the_reference_date_moves_every_birthdate_by_the_same_amount
      base = Fake.person(seed: 3)
      later = Fake.person(seed: 3, reference_date: Date.new(2030, 1, 1))
      assert_equal Date.new(2030, 1, 1) - Fake::DEFAULT_REFERENCE_DATE, later.birthdate - base.birthdate
      assert_equal base.to_h.except(:birthdate), later.to_h.except(:birthdate)
    end

    def test_default_reference_date_is_fixed_not_today
      assert_equal Date.new(2026, 1, 1), Fake::DEFAULT_REFERENCE_DATE
    end

    def test_addresses
      people.each do |person|
        address = person.address
        assert_equal %i[street number complement neighborhood city uf cep], address.keys
        assert_includes Fake::Data::STREET_TYPES, address[:street].split.first
        assert_match(/\A[1-9]\d{0,3}\z/, address[:number])
        assert(address[:complement].nil? || Fake::Data::COMPLEMENTS.include?(address[:complement]))
        assert_includes Fake::Data::NEIGHBORHOODS, address[:neighborhood]
      end
    end

    def test_to_h_is_json_friendly
      parsed = JSON.parse(JSON.generate(Fake.people(2, seed: 5).map(&:to_h)))
      assert_equal 2, parsed.length
      assert_match(/\A\d{4}-\d{2}-\d{2}\z/, parsed.first["birthdate"])
      assert_equal %w[name gender cpf email phone phone_e164 birthdate address], parsed.first.keys
    end

    def test_the_data_looks_varied
      assert_equal %w[F M], people.map(&:gender).uniq.sort
      assert_operator people.map { |person| person.address[:uf] }.uniq.length, :>=, 20
      assert_operator people.map(&:name).uniq.length, :>=, 145
      assert_operator people.map(&:cpf).uniq.length, :==, 150
    end

    def test_data_tables_are_consistent
      Fake::Data::CITIES.each do |name, uf, ddd|
        assert_equal uf, Phone::AREA_CODES[ddd], "#{name}: DDD #{ddd} belongs to #{Phone::AREA_CODES[ddd].inspect}, not #{uf}"
      end
      assert_equal UF::CODES, Fake::Data::CITIES.map { |_, uf, _| uf }.uniq.sort, "every state has at least one city"
      assert_equal Fake::Data::CITIES.length, Fake::Data::CITIES.map { |name, uf, _| [name, uf] }.uniq.length
      [Fake::Data::FEMALE_NAMES, Fake::Data::MALE_NAMES, Fake::Data::SURNAMES, Fake::Data::STREET_NAMES,
       Fake::Data::NEIGHBORHOODS, Fake::Data::COMPLEMENTS, Fake::Data::EMAIL_DOMAINS].each do |list|
        assert_equal list.uniq.length, list.length, "duplicates in #{list.first(3)}"
        assert list.all? { |word| word.is_a?(String) && !word.strip.empty? }
      end
      assert_empty Fake::Data::FEMALE_NAMES & Fake::Data::MALE_NAMES
    end

    def test_data_is_frozen
      assert_predicate Fake::Data::CITIES, :frozen?
      assert_predicate Fake::Data::SURNAMES, :frozen?
    end
  end
end
