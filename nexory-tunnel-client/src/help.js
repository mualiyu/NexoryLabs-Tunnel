export function printHelp() {
  console.log(`nexory-tunnel — expose local ports through your Nexory tunnel server

Usage:
  nexory-tunnel login
  nexory-tunnel http <local_port> [subdomain]
  nexory-tunnel tcp <local_port> [remote_port]
  nexory-tunnel version

Examples:
  nexory-tunnel login
  nexory-tunnel http 3000
  nexory-tunnel http 3000 myapp
  nexory-tunnel tcp 22 25022

Config: ~/.config/nexory-tunnel/config
`);
}
