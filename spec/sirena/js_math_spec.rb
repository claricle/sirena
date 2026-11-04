# frozen_string_literal: true

require "sirena/js_math"

RSpec.describe Sirena::JsMath do
  # Expected values are what Chrome 156 (V8, x86_64) returned for Math.*,
  # picked among inputs where an uncorrected libm can differ in the last bit.
  {
    sin: [[-6.341925849672407, -0.058706768089675856],
          [-110.9275477938354, 0.8259046885655723],
          [-5.427913827355951, 0.7547490384112616]],
    cos: [[-6.341925849672407, 0.9982752703440394],
          [-110.9275477938354, -0.5638097599416004],
          [-5.427913827355951, 0.6560136347800067]],
    atan: [[-9.059894070960581, -1.46086475079001],
           [-0.00013212870265770025, -0.00013212870188879954],
           [6.057033850811422, 1.407174977757308]],
    log: [[47.00529645297093, 3.8502602858497057],
          [5.269090547644256e-34, -76.62603538574098],
          [112.29186947557493, 4.721101459083984]],
    log10: [[47.00529645297093, 1.672146796035764],
            [5.269090547644256e-34, -33.27826433815062],
            [112.29186947557493, 2.050348312185565]],
  }.each do |name, vectors|
    describe ".#{name}" do
      vectors.each do |input, expected|
        it "returns #{expected} for #{input}" do
          expect(described_class.public_send(name, input)).to eq(expected)
        end
      end
    end
  end

  describe ".atan2" do
    inf = Float::INFINITY
    [
      [[-152.617277876973, -0.006897708921137688], -1.5708415229156267],
      [[-4898.588226116531, 28.219901551297532], -1.5650355671482097],
      [[-606.2350669283416, -667.9175302010084], -2.404567302870452],
      [[0.0, -1.0], Math::PI],
      [[-0.0, -1.0], -Math::PI],
      [[1.0, 0.0], Math::PI / 2],
      [[inf, -inf], 3 * (Math::PI / 4)],
      [[1.0, inf], 0.0],
    ].each do |args, expected|
      it "returns #{expected} for #{args}" do
        expect(described_class.atan2(*args)).to eq(expected)
      end
    end

    [[1.0, 3e10], [-7.0, 1e12], [2.0**-40, 1.0]].each do |y, x|
      it "returns the correctly rounded ratio when atan2(#{y}, #{x}) is tiny" do
        expect(described_class.atan2(y, x)).to eq(y / x)
      end
    end

    it "returns NaN for a NaN argument" do
      expect(described_class.atan2(Float::NAN, 1.0)).to be_nan
    end
  end

  describe ".hypot" do
    {
      [-152.617277876973, -0.006897708921137688] => 152.61727803284782,
      [-606.2350669283416, -667.9175302010084] => 902.01706387597,
      [0.0, 0.0] => 0.0,
      [Float::NAN, Float::INFINITY] => Float::INFINITY,
    }.each do |args, expected|
      it "matches V8 for hypot#{args}" do
        expect(described_class.hypot(*args)).to eq(expected)
      end
    end

    it "returns NaN when NaN meets a finite value" do
      expect(described_class.hypot(Float::NAN, 1.0)).to be_nan
    end
  end

  describe ".pow" do
    {
      [2, 10.0] => 1024.0,
      [9, 0.5] => 3.0,
      [5.0, 0.0] => 1.0,
      [-8.0, 3.0] => -512.0,
      [0.0, -1.0] => Float::INFINITY,
      [10.0, 400.0] => Float::INFINITY,
      [2.0, Float::INFINITY] => Float::INFINITY,
      [0.5, Float::INFINITY] => 0.0,
      [-2.0, -Float::INFINITY] => 0.0,
      [0.5, -Float::INFINITY] => Float::INFINITY,
    }.each do |args, expected|
      it "returns #{expected} for pow#{args}" do
        expect(described_class.pow(*args)).to eq(expected)
      end
    end

    [[-8.0, 0.5], [1.0, Float::INFINITY]].each do |args|
      it "returns NaN for pow#{args}" do
        expect(described_class.pow(*args)).to be_nan
      end
    end
  end

  [[1.0, 0.0], [10.0, 1.0], [1000.0, 3.0],
   [1e15, 15.0]].each do |input, expected|
    it "keeps log10(#{input}) exact" do
      expect(described_class.log10(input)).to eq(expected)
    end
  end

  {
    sin: [1e22, -0.8522008497671888],
    cos: [1e22, 0.523214785395139],
  }.each do |name, (input, expected)|
    it "reduces #{name}(1e22) beyond 2**20 radians exactly" do
      expect(described_class.public_send(name, input)).to eq(expected)
    end
  end

  describe "special values (ECMAScript Math semantics)" do
    inf = Float::INFINITY
    nan = Float::NAN
    pi = Math::PI

    # [function, arguments, expected]; signed zeros are compared by sign.
    {
      [:atan, inf] => pi / 2, [:atan, -inf] => -pi / 2,
      [:hypot] => 0.0, [:hypot, nan, inf] => inf, [:hypot, -inf, 1.0] => inf,
      [:log, 0.0] => -inf, [:log, inf] => inf,
      [:log10, inf] => inf,
      [:pow, -0.0, -3.0] => -inf, [:pow, -0.0, -2.0] => inf,
      [:pow, 0.0, 3.0] => 0.0, [:pow, -inf, 3.0] => -inf,
      [:pow, 2.0, -2000.0] => 0.0, [:pow, 2.0, 2000.0] => inf,
      [:atan2, 1.0, -inf] => pi, [:atan2, inf, 1.0] => pi / 2,
      [:atan2, inf, inf] => pi / 4
    }.each do |(name, *args), expected|
      it "returns #{expected} for #{name}#{args}" do
        expect(described_class.public_send(name, *args)).to eq(expected)
      end
    end

    [[:sin, nan], [:sin, inf], [:cos, -inf], [:atan, nan], [:log, -1.0]]
      .each do |name, arg|
      it "returns NaN for #{name}(#{arg})" do
        expect(described_class.public_send(name, arg)).to be_nan
      end
    end

    [[:atan, [-0.0]], [:pow, [-0.0, 3.0]], [:atan2, [-0.0, 1.0]],
     [:atan2, [-1.0, inf]]].each do |name, args|
      it "returns negative zero for #{name}#{args}" do
        expect(1.0 / described_class.public_send(name, *args)).to eq(-Float::INFINITY)
      end
    end
  end
end
