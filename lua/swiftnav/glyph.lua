local M = {}

local GLYPH = {
  Struct = 'S',
  Class = 'S',
  Actor = 'A',
  Enum = 'E',
  Protocol = 'P',
  Interface = 'P',
  Function = 'f',
  Method = 'f',
  Constructor = 'i',
  Property = 'v',
  Field = 'v',
  Variable = 'v',
  Constant = 'k',
  Module = 'm',
  Extension = 'e',
  File = '·',
}

local GROUP = {
  Struct = 'SwiftNavKindType',
  Class = 'SwiftNavKindType',
  Actor = 'SwiftNavKindType',
  Enum = 'SwiftNavKindType',
  Protocol = 'SwiftNavKindType',
  Interface = 'SwiftNavKindType',
  Function = 'SwiftNavKindFunction',
  Method = 'SwiftNavKindFunction',
  Constructor = 'SwiftNavKindFunction',
  Property = 'SwiftNavKindValue',
  Field = 'SwiftNavKindValue',
  Variable = 'SwiftNavKindValue',
  Constant = 'SwiftNavKindValue',
  Module = 'SwiftNavKindModule',
  Extension = 'SwiftNavKindType',
  File = 'SwiftNavKindFile',
}

function M.get(kind)
  return GLYPH[kind] or '·', GROUP[kind] or 'SwiftNavKindValue'
end

return M
