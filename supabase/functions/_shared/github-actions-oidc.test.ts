import { trustedFarmWatchMaterializationEvent } from './github-actions-oidc.ts'

function assert(value: unknown, message: string) {
  if (!value) throw new Error(message)
}

const terrain = 'pmicka/Cadastory/.github/workflows/farm-watch-neutral-primitives.yml@refs/heads/main'
const mast = 'pmicka/Cadastory/.github/workflows/farm-watch-mast-capacity.yml@refs/heads/main'
const other = 'pmicka/Cadastory/.github/workflows/farm-watch-lidar-physical.yml@refs/heads/main'

Deno.test('terrain renewal schedule is explicitly trusted', () => {
  assert(trustedFarmWatchMaterializationEvent(terrain, 'schedule'), 'terrain schedule rejected')
  assert(trustedFarmWatchMaterializationEvent(terrain, 'issues'), 'existing issue trigger rejected')
})

Deno.test('schedule trust does not expand to unrelated materialization workflows', () => {
  assert(!trustedFarmWatchMaterializationEvent(other, 'schedule'), 'unrelated schedule accepted')
  assert(!trustedFarmWatchMaterializationEvent(mast, 'schedule'), 'mast schedule accepted')
  assert(!trustedFarmWatchMaterializationEvent(terrain, 'workflow_dispatch'), 'terrain dispatch accepted')
})

Deno.test('existing mast workflow_dispatch exception is preserved', () => {
  assert(trustedFarmWatchMaterializationEvent(mast, 'workflow_dispatch'), 'mast dispatch rejected')
  assert(!trustedFarmWatchMaterializationEvent(other, 'workflow_dispatch'), 'unrelated dispatch accepted')
})
