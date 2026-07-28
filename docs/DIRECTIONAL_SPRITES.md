# Directional character sprites

Character packs can declare the direction their source artwork faces:

```json
{
  "source_facing": "left"
}
```

Supported values are `"left"` and `"right"`. The default is `"left"` so
existing character packs keep their previous behavior.

The desktop pet automatically mirrors the sprite when autonomous movement or
dragging goes in the opposite direction.

An individual action can override the pack default:

```json
{
  "source_facing": "left",
  "actions": {
    "move": {
      "file": "animations/move.png",
      "source_facing": "right"
    }
  }
}
```

Use the direction the character's body is traveling toward, not the direction
their eyes happen to look.
