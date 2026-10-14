# frozen_string_literal: true

# A stand-in for one process of an app, for the app runner's specs and the
# Preview tab's Cypress run (plan 012). Standard library only, so it starts
# in any Ruby without a bundle.
#
#   --name NAME          what its page says; default "app"
#   --port-env VAR       listen on $VAR; default PORT
#   --port N             listen on N instead: an app that ignored its port
#   --delay SECONDS      wait before listening, so an order is observable
#   --exit STATUS        exit at once with STATUS, never listening
#   --silent             never listen, never exit
#   --deny               send X-Frame-Options: DENY
#   --sibling-env VAR    look, on start, whether the sibling on $VAR answers;
#                        the page says, as #sibling
#   --record FILE        and write it to FILE too
require "socket"

# A program the specs start, not a spec: printing is what it is for.
# rubocop:disable RSpec/Output

options = { name: "app", port_env: "PORT" }
args = ARGV.dup
until args.empty?
  flag = args.shift
  case flag
  when "--name" then options[:name] = args.shift
  when "--port-env" then options[:port_env] = args.shift
  when "--port" then options[:port] = Integer(args.shift)
  when "--delay" then options[:delay] = Float(args.shift)
  when "--exit" then options[:exit] = Integer(args.shift)
  when "--silent" then options[:silent] = true
  when "--deny" then options[:deny] = true
  when "--record" then options[:record] = args.shift
  when "--sibling-env" then options[:sibling_env] = args.shift
  else abort "server.rb: unknown flag #{flag}"
  end
end

$stdout.sync = true
puts "#{options[:name]} starting as #{Process.pid}"
exit options[:exit] if options[:exit]
sleep if options[:silent]

if options[:sibling_env]
  sibling = Integer(ENV.fetch(options[:sibling_env]))
  answered = begin
    Socket.tcp("127.0.0.1", sibling, connect_timeout: 1).close
    true
  rescue SystemCallError
    false
  end
  options[:sibling] = "#{answered ? "answered" : "refused"} #{sibling}"
  File.write(options[:record], "#{options[:sibling]}\n") if options[:record]
end

sleep options[:delay] if options[:delay]
port = options[:port] || Integer(ENV.fetch(options[:port_env]))
server = TCPServer.new("127.0.0.1", port)
puts "#{options[:name]} listening on #{port}"
Signal.trap("TERM") { exit 0 }

page = <<~HTML
  <!doctype html>
  <html lang="en"><head><meta charset="utf-8"><title>#{options[:name]}</title></head>
  <body><h1 id="name">#{options[:name]}</h1><p>pid <span id="pid">#{Process.pid}</span></p>
  <p>port <span id="port">#{port}</span></p>
  <p>sibling <span id="sibling">#{options[:sibling] || "none"}</span></p></body></html>
HTML
headers = ["Content-Type: text/html; charset=utf-8", "Content-Length: #{page.bytesize}", "Connection: close"]
headers << "X-Frame-Options: DENY" if options[:deny]
response = "HTTP/1.1 200 OK\r\n#{headers.join("\r\n")}\r\n\r\n#{page}"

loop do
  client = server.accept
  Thread.new(client) do |socket|
    socket.readpartial(8192)
    socket.write(response)
  rescue EOFError, SystemCallError
    nil
  ensure
    socket.close
  end
end
# rubocop:enable RSpec/Output
