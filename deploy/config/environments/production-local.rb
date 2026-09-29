# Allow HTTP on the VPS IP (no Secure cookies / HSTS).
# Remove when TLS is terminated in front of Canvas.
Rails.application.configure do
  config.force_ssl = false
  config.public_file_server.enabled = true
end
