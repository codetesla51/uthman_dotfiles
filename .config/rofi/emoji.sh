#!/usr/bin/env bash
# Emoji picker: rofi dmenu + wl-copy (Wayland clipboard)
EMOJIS="😀  Grinning face
😄  Smiling face with open mouth
😁  Beaming face
😂  Face with tears of joy
🤣  Rolling on the floor laughing
😊  Smiling face with smiling eyes
😍  Heart eyes
😘  Face blowing a kiss
😜  Winking face with tongue
🤔  Thinking face
🤨  Raised eyebrow
😎  Smiling face with sunglasses
🥳  Partying face
😢  Crying face
😭  Loudly crying face
😡  Angry face
😱  Face screaming in fear
😴  Sleeping face
🤯  Exploding head
😇  Smiling face with halo
😈  Smiling face with horns
💀  Skull
👻  Ghost
🤖  Robot
👽  Alien
🫶  Heart hands
👍  Thumbs up
👎  Thumbs down
👏  Clapping hands
🙏  Folded hands
👊  Oncoming fist
✌️  Victory hand
🤞  Crossed fingers
🤟  Love-you gesture
💪  Flexed biceps
🙌  Raising hands
👀  Eyes
🧠  Brain
❤️  Red heart
🧡  Orange heart
💛  Yellow heart
💚  Green heart
💙  Blue heart
💜  Purple heart
🖤  Black heart
🤍  White heart
💯  Hundred points
🔥  Fire
⭐  Star
✨  Sparkles
🎉  Party popper
🎂  Birthday cake
🎁  Wrapped gift
⚡  High voltage
🌙  Crescent moon
☀️  Sun
☁️  Cloud
🌈  Rainbow
❄️  Snowflake
💧  Droplet
☕  Hot beverage
🍺  Beer mug
🍻  Clinking glasses
🍕  Pizza
🍔  Hamburger
🍟  French fries
🍎  Red apple
🍀  Four leaf clover
🏆  Trophy
🎮  Video game
🎧  Headphone
📱  Mobile phone
💻  Laptop
⌨️  Keyboard
🖥️  Desktop computer
📧  E-mail
💬  Speech balloon
📌  Pushpin
🗓️  Calendar
🔒  Lock
🔑  Key
💡  Light bulb
🚀  Rocket
✈️  Airplane
🚗  Automobile
🏠  House
🏖️  Beach
🌍  Globe showing Europe-Africa
⏰  Alarm clock
✅  Check mark
❌  Cross mark
⚠️  Warning
🚨  Police car light
🛑  Stop sign
➡️  Right arrow
⬆️  Up arrow
⬇️  Down arrow
↩️  Left arrow curving right
"

pick=$(printf '%s\n' "$EMOJIS" | rofi -dmenu -theme ~/.config/rofi/list.rasi -p '😀  Emoji' -i -lines 12)
[[ -z "$pick" ]] && exit 0
emoji="${pick%%  *}"
printf '%s' "$emoji" | wl-copy
