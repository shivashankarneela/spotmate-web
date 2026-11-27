// Static campaign validation, requiring no game server or payment backend.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync('web/games/space_shooter/index.html', 'utf8');
const inline = html.match(/<script>\s*([\s\S]*?)<\/script>/);
assert(inline, 'Game must contain its playable script');
new vm.Script(inline[1], { filename: 'space-shooter-inline.js' });

const begin = inline[1].indexOf('const LEVELS = [');
const end = inline[1].indexOf('let selectedStartLevel = 0;', begin);
assert(begin >= 0 && end > begin, 'Level generator must be accessible');
const script = inline[1].slice(begin, end) + '\n globalThis.campaign = LEVELS;';
const scope = {};
vm.runInNewContext(script, scope, { timeout: 2000 });
const levels = scope.campaign;
assert.equal(levels.length, 100, 'Exactly 100 missions');
assert.equal(new Set(levels.map(l => l.name)).size, 100, 'Each mission has a unique challenge title');
assert.equal(levels.filter(l => l.elite).length, 10, '10 chapter-end elite bosses');
assert(levels.every((l, i) => l.id === i + 1 && l.enemies.length && l.boss.hp > 0));
assert(levels[99].boss.hp > levels[9].boss.hp * 2, 'Late-game boss must scale substantially');
assert.equal(new Set(levels.map(l => l.challenge.name)).size, 10, '10 hazard archetypes');
// Guard the player-weapon progression against future UI and gameplay regressions.
assert(html.includes('id="hudWeapon"'), 'Weapon tier must be visible on HUD');
assert(inline[1].includes("state.weaponTier = Math.min(5, state.weaponTier + 1)"),
  'Weapon upgrades must stop at tier 5');
assert(inline[1].includes("if (pu.kind === 'WEAPON')"),
  'A distinct collectible must upgrade the primary gun');
assert(inline[1].includes('firePrimaryWeapon();'),
  'Main auto-fire must use the upgraded gun');
assert(inline[1].includes("state.weaponTier = 1;"),
  'A new run must start with the basic cannon');
assert(inline[1].includes("kind: tier === 5 ? 'plasma' : 'normal'"),
  'Tier 5 must unlock plasma projectiles');
assert(inline[1].includes("state.autoSpecial = true;"),
  'Existing automatic special pickup behavior must remain');
assert.equal(new Set(levels.map(l => l.boss.name)).size, 100, 'All bosses must have unique names');
assert.equal(new Set(levels.map(l => l.boss.attackFamily + '/' + l.boss.attackVariant)).size, 100,
  'Every boss must have a different attack configuration');
assert.equal(levels.filter(l => l.boss.tentacles).length, 20,
  'Tentacle and elite boss encounters must be present');
assert(inline[1].includes('state.weaponTier = Math.max(1, previousTier - 1)'),
  'Registered hits must downgrade weapons without going below basic tier');
assert(inline[1].includes("state.weaponTier = 1;\n        state.specialType = 'MISSILE'"),
  'Every level should reset both regular and special weapon upgrades');
assert(inline[1].includes('loadArtworkForLevel(idx);'),
  'Every level must load its own supplied background');
assert(inline[1].includes("art/backgrounds/level_") &&
  inline[1].includes("art/enemies/galaxy_"),
  'The supplied art bundle paths must be mapped for every level');
console.log('PASS: script syntax, 100 unique missions, 10 boss milestones, scaling HP');
console.log('PASS: 100 boss attack variants, 20 tentacle bosses, level reset, damage downgrade, image mapping');
console.log('PASS: five-tier player cannon, collectibles, HUD and auto specials');
