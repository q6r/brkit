# frozen_string_literal: true

module Brkit
  # CRC-16/CCITT-FALSE: polynomial 0x1021, initial value 0xFFFF, no input or
  # output reflection, no final XOR. This is the checksum of the EMV QR code
  # payload (field 63) used by PIX; the check value for +"123456789"+ is 0x29B1.
  module CRC16
    POLYNOMIAL = 0x1021
    INITIAL = 0xFFFF

    # 256-entry lookup table, computed once at load time.
    TABLE = Array.new(256) do |index|
      8.times.inject(index << 8) do |crc, _|
        shifted = (crc << 1) & 0xFFFF
        crc.anybits?(0x8000) ? shifted ^ POLYNOMIAL : shifted
      end
    end.freeze

    class << self
      # @param data [String] processed byte by byte (any encoding)
      # @param initial [Integer] starting register value
      # @return [Integer] 16-bit checksum
      def checksum(data, initial: INITIAL)
        data.each_byte.inject(initial) do |crc, byte|
          ((crc << 8) & 0xFFFF) ^ TABLE[((crc >> 8) ^ byte) & 0xFF]
        end
      end

      # @param data [String]
      # @return [String] four uppercase hexadecimal characters, as written in a BR Code
      def hex(data)
        format("%04X", checksum(data))
      end

      # Runs the checksum and records every byte, to show how the register evolves.
      #
      # Each step feeds one byte: +:index+ is the byte xor the register's high byte, +:table+ the lookup table
      # entry for it and +:crc+ the register afterwards (the last +:crc+ equals {checksum}).
      #
      # @param data [String] processed byte by byte (any encoding)
      # @param initial [Integer] starting register value
      # @return [Array<Hash{Symbol=>Integer}>] one step per byte, in order
      def trace(data, initial: INITIAL)
        crc = initial
        data.each_byte.map do |byte|
          index = ((crc >> 8) ^ byte) & 0xFF
          crc = ((crc << 8) & 0xFFFF) ^ TABLE[index]
          { byte: byte, index: index, table: TABLE[index], crc: crc }
        end
      end
    end
  end
end
