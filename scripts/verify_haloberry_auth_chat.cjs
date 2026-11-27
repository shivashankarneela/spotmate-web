// Lightweight regression guards for the HaloBerry login, chat receipts, and theme.
// Flutter compilation and integration tests remain separate CI steps.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const read = path => fs.readFileSync(path, 'utf8');
const auth = read('lib/features/auth/presentation/auth_screen.dart');
const gate = read('lib/main.dart');
const chat = read('lib/features/chat/presentation/chat_screen.dart');
const chatTheme = read('lib/core/widgets/spotmate_chat_theme.dart');

assert(auth.includes('Forgot password?'), 'Sign-in UI must offer password recovery');
assert(auth.includes('resetPasswordForEmail('), 'Recovery must use Supabase reset email');
assert(auth.includes('if (!_isSignUp)'), 'Recovery link must be limited to sign-in');
assert(auth.includes('class PasswordResetScreen'), 'Recovery must have a new-password screen');
assert(auth.includes('isStrongPassword(newPassword)'), 'Password strength must be validated');
assert(auth.includes('newPassword != _confirm.text'), 'Password confirmation is required');
assert(auth.includes('UserAttributes(password: newPassword)'), 'Update the password through Supabase');
assert(gate.includes('AuthChangeEvent.passwordRecovery'), 'Recovery sessions must be handled explicitly');
assert(gate.includes('if (_passwordRecovery)'), 'Recovery screen must take priority over regular login');
assert(chat.includes("final isRead = msg['read_at'] != null"), 'Read indicator must come from persisted read_at');
assert(chat.includes('isRead ? Icons.visibility_rounded : Icons.check_rounded'), 'Use an eye only for read outgoing messages');
assert(chat.includes('if (isMe) ...['), 'Receipts must be visible to sender only');
assert(chatTheme.includes("name: 'HaloBerry'"), 'HaloBerry must remain default chat theme');
assert(gate.includes('0xFFFAF8F5') && gate.includes('0xFF517C6E'), 'Global theme must include ivory and mint');

console.log('PASS: password recovery, private read eye, sender-only receipts, HaloBerry theme');
