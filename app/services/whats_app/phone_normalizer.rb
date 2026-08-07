module WhatsApp
  # Centralized phone digit normalization shared by the inbound webhook and
  # every outbound sender. Historically each caller had its own copy of this
  # logic; when only the inbound side (webhooks_controller.rb) learned the
  # Mexico 521->52 rule, outbound-stored numbers and inbound-computed numbers
  # went out of sync and legitimate replies started showing up as UNMATCHED.
  class PhoneNormalizer
    def self.normalize(phone)
      digits = phone.to_s.gsub(/\D/, '')

      normalize_mexico(digits)
    end

    # Meta may send Mexican mobile numbers as 521XXXXXXXXXX, while our
    # database stores/expects them as 52XXXXXXXXXX.
    def self.normalize_mexico(digits)
      return digits unless digits.start_with?('521') && digits.length == 13

      "52#{digits[3..-1]}"
    end
    private_class_method :normalize_mexico

    # Brazilian mobile numbers can legitimately appear with or without the
    # "9" inserted after the DDD (55 + DDD(2) + [9] + 8-digit subscriber
    # number), depending on the source (Meta's inbound wa_id, older CSV
    # exports, manually-entered numbers). Rather than picking one canonical
    # form and rewriting normalize_phone's output (which risks breaking
    # already-matching historical data stored in whichever format it
    # happens to be in), this returns every plausible variant so matching
    # code can search for all of them. It must NEVER be used to decide what
    # gets stored/displayed -- only to widen a lookup.
    def self.brazil_match_variants(digits)
      return [digits] unless digits.to_s.start_with?('55')

      rest = digits[2..-1].to_s
      variants = [digits]

      if rest.length == 10
        # DDD + 8-digit subscriber number, missing the "9"
        variants << "55#{rest[0, 2]}9#{rest[2..-1]}"
      elsif rest.length == 11 && rest[2] == '9'
        # DDD + "9" + 8-digit subscriber number, has the "9"
        variants << "55#{rest[0, 2]}#{rest[3..-1]}"
      end

      variants.uniq
    end
  end
end
