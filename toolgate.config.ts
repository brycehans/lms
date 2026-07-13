import { definePolicy } from '/Users/bryce/.bun/install/global/node_modules/@brycehanscomb/toolgate/src/index'
import { safeBashCommandOrPipeline } from '/Users/bryce/.bun/install/global/node_modules/@brycehanscomb/toolgate/policies/parse-bash-ast'

// Scripts declared in package.json.
const packageScripts = new Set(['dev', 'build', 'start', 'lint', 'typecheck'])

export default definePolicy([
  {
    name: 'Allow next-devtools MCP',
    description:
      'Permits all tool calls from the next-devtools MCP server (browser_eval, nextjs_call, nextjs_docs, nextjs_index)',
    action: 'allow',
    handler: async (call) => {
      if (call.tool.startsWith('mcp__next-devtools__')) return true
      return
    },
  },
  {
    name: 'Allow package.json scripts',
    description:
      'Permits running the scripts declared in package.json via pnpm/npm/yarn, optionally piped through safe filters',
    action: 'allow',
    handler: async (call) => {
      const tokens = await safeBashCommandOrPipeline(call)
      if (!tokens) return

      const [cmd, ...rest] = tokens
      if (cmd !== 'pnpm' && cmd !== 'npm' && cmd !== 'yarn') return

      // Optional `run`, then the script name.
      const script = rest[0] === 'run' ? rest[1] : rest[0]
      if (script && packageScripts.has(script)) return true

      return
    },
  },
])

// Disable built-in or inherited policies by name.
// Use `toolgate disable --json` to see all loaded policies.
export const disable: string[] = []
