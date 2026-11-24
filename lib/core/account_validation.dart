const usernameRequirements = 'Use letters, numbers, underscores or hyphens.';
const passwordRequirements =
    'Use at least 8 characters, including uppercase, lowercase and a special character.';

bool isValidUsername(String value) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

bool isStrongPassword(String value) =>
    value.runes.length >= 8 &&
    RegExp(r'[a-z]').hasMatch(value) &&
    RegExp(r'[A-Z]').hasMatch(value) &&
    RegExp(r'[\p{P}\p{S}]', unicode: true).hasMatch(value);
