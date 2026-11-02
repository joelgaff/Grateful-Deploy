# Masks secrets in a line of command output (Kamal deploys, app logs) before
# it is stored or shown. Errs toward masking: a hidden harmless value costs
# little, a shown secret costs a lot. Rules run in order; each is idempotent.
module SecretScrubber
  FILTERED = "[FILTERED]".freeze
  # Shown instead of a line that hits Ruby's regex timeout: hiding it keeps the
  # deploy or log going without ever showing a line that wasn't checked.
  TOO_LONG = "[line hidden: too long to check for secrets]".freeze

  # Key names that hold secrets, in any case or style (password, apiKey, X-Auth-Token…).
  # Each name is read once from its first character (a look ahead for the
  # keyword, then the whole name with no backtracking), so a long line can't
  # make the search retry every split and hit Ruby's regex timeout.
  SECRET_NAME = /
    (?<![\w.-])(?=[\w.-]*?
    (?:passw(?:or)?d|passphrase|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|
       master[_-]?key|key[_-]?base|client[_-]?secret|credentials?|auth(?!or)|session|cookie|
       signature|otp|salt))
    [\w.-]*+
  /xi
  # Upper-case env names ending in KEY (STRIPE_KEY, GEMINI_API_KEY).
  ENV_KEY_NAME = /(?<![A-Z0-9_])(?=[A-Z0-9_]*?_KEY\b)[A-Z0-9_]*+/

  # Well-known token formats, masked wherever they appear. The dotted ones
  # start only where a run of token characters starts and never give
  # characters back ((?>…), an atomic group; in Ruby {n,}+ means "repeat",
  # not "possessive"), so a long line is read once, not once per "eyJ".
  KNOWN_TOKENS = Regexp.union(
    /\bgh[pousr]_[A-Za-z0-9]{20,}/,                       # GitHub
    /\bgithub_pat_[A-Za-z0-9_]{20,}/,                     # GitHub fine-grained
    /\b[sr]k_(?:live|test)_[A-Za-z0-9]{10,}/,             # Stripe
    /\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/,                      # AWS access key
    /\bAIza[A-Za-z0-9_-]{30,}/,                           # Google
    /\bxox[abprs]-[A-Za-z0-9-]{10,}/,                     # Slack
    /\bsk-[A-Za-z0-9_-]{20,}/,                            # OpenAI / Anthropic
    /\bglpat-[A-Za-z0-9_-]{20,}/,                         # GitLab
    /\bnpm_[A-Za-z0-9]{30,}/,                             # npm
    /\bhf_[A-Za-z0-9]{30,}/,                              # Hugging Face
    /(?<![A-Za-z0-9_-])SG\.(?>[A-Za-z0-9_-]{16,})\.[A-Za-z0-9_-]{16,}/, # SendGrid
    /\bmlsn\.[A-Za-z0-9]{32,}/,                           # MailerSend
    /(?<![A-Za-z0-9_-])eyJ(?>[A-Za-z0-9_-]{8,})\.eyJ(?>[A-Za-z0-9_-]{8,})\.[A-Za-z0-9_-]{8,}/, # JWT
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/
  )

  # Authorization: Bearer x / Basic x / token x, and bare "Bearer x".
  AUTH_HEADER = /\b(authorization\s*[:=]\s*["']?)(?:(bearer|basic|token|digest)\s+)?[^\s"',;]+/i
  BEARER = /\b(bearer)\s+[A-Za-z0-9._~+\/-]+=*/i
  # Cookie: a=1; b=2 — every cookie value.
  COOKIE_HEADER = /\b((?:set-)?cookie\s*:\s*)(.*)/i
  # scheme://user:password@host
  URL_PASSWORD = %r{(\b[a-z][a-z0-9+.-]*://[^/\s:@]*:)[^@\s/]+(@)}i
  # Email addresses (also URL-encoded, %40), as Rails' filter_parameters does.
  # A host needs a letter TLD, so root@203.0.113.30 and user@localhost stay.
  EMAIL = /[A-Za-z0-9._%+-]+(?:@|%40)(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}\b/

  QUOTED_PAIR = /(["']?)(#{SECRET_NAME}|#{ENV_KEY_NAME})\1(\s*(?:=>|[:=])\s*)(["'])(.*?)\4/
  # The value attribute is looked for within 200 characters of the name (one
  # tag), so a long line of name= attributes stays fast.
  HTML_VALUE = /(name=["'](?:#{SECRET_NAME})["'][^>]{0,200}?\bvalue=)(["'])(.*?)\2/
  BARE_PAIR = /\b(#{SECRET_NAME}|#{ENV_KEY_NAME})(\s*(?:=>|[:=])\s*)(?!["'\[])([^\s"',;&}<>]+)/

  # 32+ char runs of token characters, checked by #secret_looking?.
  LONG_TOKEN = %r{(?<![A-Za-z0-9+/_\-])(?<!sha256:)[A-Za-z0-9+/_\-]{32,}={0,2}}

  def self.scrub(line)
    mask(line)
  rescue Regexp::TimeoutError
    TOO_LONG
  end

  def self.mask(line)
    line = line.gsub(KNOWN_TOKENS, FILTERED)
    line = line.gsub(URL_PASSWORD) { "#{$1}#{FILTERED}#{$2}" }
    line = line.gsub(EMAIL, FILTERED)
    line = line.gsub(COOKIE_HEADER) { "#{$1}#{$2.gsub(/=[^;]*/, "=#{FILTERED}")}" }
    line = line.gsub(AUTH_HEADER) { "#{$1}#{"#{$2} " if $2}#{FILTERED}" }
    line = line.gsub(BEARER) { "#{$1} #{FILTERED}" }
    line = line.gsub(HTML_VALUE) { "#{$1}#{$2}#{FILTERED}#{$2}" }
    line = line.gsub(QUOTED_PAIR) { "#{$1}#{$2}#{$1}#{$3}#{$4}#{FILTERED}#{$4}" }
    line = line.gsub(BARE_PAIR) { $3 == FILTERED ? $& : "#{$1}#{$2}#{FILTERED}" }
    line.gsub(LONG_TOKEN) { |token| secret_looking?(token) ? FILTERED : token }
  end
  private_class_method :mask

  # A 40-char hex is a git sha (Kamal's image version), so it stays visible.
  # Runs joined by "-", "_" or "/" (container names, paths) must look like
  # base64 (mixed case and digits); a single unbroken run only needs letters
  # and digits (lowercase or base32 keys).
  def self.secret_looking?(token)
    return token.length != 40 if token.match?(/\A\h+\z/)
    return false unless token.match?(/[A-Za-z]/) && token.match?(/\d/)
    return true if token.match?(/\A[A-Za-z0-9]+={0,2}\z/)

    token.match?(/[A-Z]/) && token.match?(/[a-z]/)
  end
end
