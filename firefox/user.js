// Firefox prefs managed via dotfiles (firefox/user.js).
// user.js is read at startup and never written by Firefox — safe to symlink.
// Allows the matugen-generated userChrome.css theme.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
