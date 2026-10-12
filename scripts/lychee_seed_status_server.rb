# frozen_string_literal: true

require "socket"

# Loopback HTTP responses used to prove that lychee rejects blocked and
# rate-limited links without depending on a public status service.
module LycheeSeedStatusServer
  STATUSES = {
    "/ready" => 204,
    "/status/403" => 403,
    "/status/429" => 429,
  }.freeze
  REASONS = {
    204 => "No Content",
    403 => "Forbidden",
    404 => "Not Found",
    429 => "Too Many Requests",
  }.freeze

  class Server
    attr_reader :port

    def initialize(port)
      @socket = TCPServer.new("127.0.0.1", port)
      @port = @socket.local_address.ip_port
    end

    def run
      loop { respond(@socket.accept) }
    rescue IOError, Errno::EBADF
      nil
    end

    def close
      @socket.close unless @socket.closed?
    end

    private

    def respond(client)
      method, path = client.gets.to_s.split
      while (line = client.gets)
        break if line == "\r\n"
      end
      status = STATUSES.fetch(path, 404)
      body = status == 204 ? "" : "#{status}\n"
      client.write(response(status, body, head: method == "HEAD"))
    ensure
      client&.close
    end

    def response(status, body, head:)
      payload = head ? "" : body
      "HTTP/1.1 #{status} #{REASONS.fetch(status)}\r\n" \
        "Content-Type: text/plain\r\n" \
        "Content-Length: #{body.bytesize}\r\n" \
        "Connection: close\r\n\r\n#{payload}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  server = LycheeSeedStatusServer::Server.new(Integer(ARGV.fetch(0, "49173")))
  %w[INT TERM].each { |signal| Signal.trap(signal) { server.close } }
  server.run
end
