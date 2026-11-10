import { randomUUID } from 'node:crypto';
import { chmod, mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

export function defaultConfigDir() {
  return process.env.SBP_GUI_CONFIG_DIR || join(homedir(), '.config', 'sing-box-proxy-gui');
}

/** 服务器清单，保存在 ~/.config/sing-box-proxy-gui/servers.json（权限 0600）。 */
export class ServerStore {
  constructor(configDir = defaultConfigDir()) {
    this.configDir = configDir;
    this.file = join(configDir, 'servers.json');
    this.servers = [];
    this.writing = Promise.resolve();
  }

  async load() {
    try {
      const raw = await readFile(this.file, 'utf8');
      const parsed = JSON.parse(raw);
      this.servers = Array.isArray(parsed.servers) ? parsed.servers : [];
    } catch (err) {
      if (err.code !== 'ENOENT') throw err;
      this.servers = [];
    }
    return this;
  }

  list() {
    return this.servers.map((s) => ({ ...s }));
  }

  get(id) {
    const server = this.servers.find((s) => s.id === id);
    return server ? { ...server } : null;
  }

  async add(value) {
    const server = { id: randomUUID(), ...value };
    this.servers.push(server);
    await this.save();
    return { ...server };
  }

  async update(id, value) {
    const index = this.servers.findIndex((s) => s.id === id);
    if (index === -1) return null;
    this.servers[index] = { ...value, id };
    await this.save();
    return { ...this.servers[index] };
  }

  async remove(id) {
    const before = this.servers.length;
    this.servers = this.servers.filter((s) => s.id !== id);
    if (this.servers.length === before) return false;
    await this.save();
    return true;
  }

  save() {
    // 串行化写入，避免并发请求互相覆盖。
    this.writing = this.writing.catch(() => {}).then(async () => {
      await mkdir(this.configDir, { recursive: true, mode: 0o700 });
      const tmp = `${this.file}.${process.pid}.tmp`;
      await writeFile(tmp, `${JSON.stringify({ servers: this.servers }, null, 2)}\n`, { mode: 0o600 });
      await chmod(tmp, 0o600);
      await rename(tmp, this.file);
    });
    return this.writing;
  }
}
