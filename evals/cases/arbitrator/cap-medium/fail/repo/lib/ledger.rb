class Ledger
  def initialize(path) = @path = path

  def append(line)
    File.open(@path, "a") { |f| f.puts(line) }
  end
end
