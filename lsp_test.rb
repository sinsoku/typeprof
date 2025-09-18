require "socket"
require "json"

host = "localhost"
port = ARGV[0].to_i # ← TypeProf をこのポートで起動しておく

socket = TCPSocket.new(host, port)

# LSP メッセージ送信
def send_message(io, hash)
  body = hash.to_json
  io.write "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  io.flush
end

# LSP メッセージ受信（1通）
def read_message(io)
  header = ""
  while (line = io.gets)
    break if line == "\r\n"
    header << line
  end
  len = header[/Content-Length: (\d+)/i, 1].to_i
  body = io.read(len)
  JSON.parse(body)
end

send_message(socket, {
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "initialize",
  "params" => {
    "workspaceFolders" => [
      {
        "uri" => "file:///Users/sinsoku/ghq/github.com/redmine/redmine",
      }
    ]
  }
})
puts JSON.pretty_generate(read_message(socket))

send_message(socket, {
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "exit",
  "params" => {}
})
puts JSON.pretty_generate(read_message(socket))
