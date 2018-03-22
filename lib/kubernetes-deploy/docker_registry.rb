# frozen_string_literal: true
require 'net/https'
require 'json'

module KubernetesDeploy
  module DockerRegistry
    extend self

    def image_digest(image_url)
      response = authenticated_request(manifest_url(image_url))
      response["docker-content-digest"]
    end

    def image_with_digest(image_url, digest = nil)
      info = url_info(image_url)
      digest ||= image_digest(image_url)
      iwd = String.new
      if (host = info[:registry]) && host != DOCKER_HUB_HOST
        iwd << host << "/"
      end
      if (user = info[:user]) && (user != "library" || iwd != "")
        iwd << user << "/"
      end
      "#{iwd}#{info[:image]}@#{digest}"
    end

    private

    DOCKER_HUB_HOST = "registry.hub.docker.com"
    IMAGE_SPEC = %r{\A(((?<registry>[^:/@]+([:]\d+)?)/)?((?<user>[^:/@]+)/))?
                      (?<image>[^:/@]+)(([:](?<tag>.+))|(@(?<digest>.+)))?\z}x

    def url_info(image_url)
      md = IMAGE_SPEC.match(image_url)
      matches = md.names.zip(md.captures).each_with_object({}) { |(k, v), h| h[k.to_sym] = v }

      raise "Invalid image specification: #{image_url}" unless matches[:image]

      matches[:registry] ||= DOCKER_HUB_HOST
      matches[:user] ||= "library"
      matches[:tag] ||= "latest" unless matches[:digest]
      matches
    end

    def manifest_url(image_url)
      u = url_info(image_url)
      "https://#{u[:registry]}/v2/#{u[:user]}/#{u[:image]}/manifests/" + (u[:tag] || u[:digest])
    end

    def bearer_field(bearer, name)
      bearer.scan(/#{name}="([^"]*)"/).last.first
    end

    def get_token(bearer)
      realm = bearer_field(bearer, "realm")
      service = bearer_field(bearer, "service")
      scope = bearer_field(bearer, "scope")
      uri = URI.parse(realm)
      uri.query = URI.encode_www_form(service: service, scope: scope)
      response = Net::HTTP.get_response(uri)
      return JSON.parse(response.body)['token'] if response.code.to_i == 200
      raise "Could no obtain token from '#{realm}'"
    end

    def authenticated_request(url, headers = {})
      headers = headers.merge("Accept": "application/vnd.docker.distribution.manifest.v2+json")

      uri = URI.parse(url)
      response = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        loop do
          request = Net::HTTP::Get.new uri
          headers.each { |k, v| request[k] = v }
          response = http.request request
          if %w(301 302 307).include?(response.code)
            uri = URI.parse(response['location'])
          else
            break
          end
        end
      end
      return response if response.code.to_i == 200

      # Authentication error interception
      if response.code.to_i == 401 && headers["Authorization"].nil?
        auth_token = response["www-authenticate"]
        req_token = get_token(auth_token)
        new_headers = headers.merge("Authorization" => "Bearer #{req_token}")
        return authenticated_request(url, new_headers)
      end

      raise "Could not perform request '#{url}', response: #{response.code} #{response.message}"
    end
  end
end
