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
console.log('PASS: script syntax, 100 unique missions, 10 boss milestones, scaling HP');
