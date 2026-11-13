class Ledger
  def initialize(path) = @path = path

  def append(line)
    File.open(@path, "w") { |f| f.puts(line) }
  end
end
