# hubot-timezone-converter

Enable hubot to convert times in user time zones during discussion.

See [`src/timezone-converter.coffee`](src/timezone-converter.coffee) for full documentation.

## Installation

In hubot project repo, run:

`npm install hubot-timezone-converter --save`

Then add **hubot-timezone-converter** to your `external-scripts.json`:

```json
[
  "hubot-timezone-converter"
]
```

## Sample Interaction

```
user1>> team meeting at 4am
hubot>> 21:00 (Eastern Standard Time)
        03:00 (Central European Time)
        04:00 (Eastern European Time)
```
