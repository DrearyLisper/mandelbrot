# Project Memory

## Phoenix LiveView Layouts
- Layout functions used via `layout: {Module, :name}` receive `@inner_content`, NOT `@inner_block`
- `@inner_block` is for component slots; `@inner_content` is for layouts wrapping LiveView renders
- Don't declare `slot :inner_block` or `attr :flash` on layout functions used as LiveView layouts — they receive assigns directly
