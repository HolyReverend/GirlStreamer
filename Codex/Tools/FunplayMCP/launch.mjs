import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// Read the local plugin settings without putting credentials in repository files.
const settingsPath = join(process.env.APPDATA, 'Godot', 'app_userdata', 'GirlStreamer', 'funplay_mcp_settings.cfg');
const settings = readFileSync(settingsPath, 'utf8');
const token = settings.match(/^auth_token="([^"\r\n]+)"/m)?.[1];
const port = settings.match(/^port=(\d+)/m)?.[1];
if (!token || !port) throw new Error('Godot MCP settings are missing. Open GirlStreamer with the Funplay MCP plugin enabled.');
process.env.FUNPLAY_GODOT_MCP_URL = 'http://127.0.0.1:' + port + '/';
process.env.FUNPLAY_GODOT_MCP_TOKEN = token;
await import('./funplay-godot-mcp.mjs');
