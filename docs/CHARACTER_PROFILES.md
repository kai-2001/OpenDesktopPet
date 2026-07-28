# Character save profiles

Each character pack must have a stable, unique `id`:

```json
{
  "id": "pink_cat_headset_girl"
}
```

Gameplay state is stored under that ID:

```text
user://profiles/pink_cat_headset_girl/save_v2.json
```

Different character IDs never share gameplay progress. Changing an ID creates
a new profile, so published character-pack IDs should not be renamed.

IDs are normalized to lowercase filenames. Spaces become underscores. Missing
or empty IDs use the `default` profile for backward compatibility.
