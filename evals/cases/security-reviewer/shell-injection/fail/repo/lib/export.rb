class Export
  def call(name)
    system("tar -czf exports/#{name}.tgz data/")
  end
end
