let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/f53517e1a532275569bb14a452359f11c3e02c03/package.dhall
        sha256:3b79aae9216456678300441ca8616b64a4b4fa520a1286dfcc418f60899d5d4a

let TechRadar =
      https://raw.githubusercontent.com/shinzui/mori-schema/f53517e1a532275569bb14a452359f11c3e02c03/extensions/tech-radar/package.dhall
        sha256:13ddc09176a770d63369db71987441c8be357889c3f3b67f044e855138434e80

in  TechRadar.TechRadar::{ recommendations =
      [ TechRadar.Recommendation::{ language = Schema.Language.Haskell
        , category = TechRadar.Category.Other "Temporal Interval"
        , package = "interval-patterns"
        , level = TechRadar.AdoptionLevel.Adopt
        , reason = Some
            "Intervals of ordered types, and their monoids under union and intersection. Properly implements Allen's interval algebra."
        , alternatives = [ "rampart" ]
        , project = Some "mori://mixphix/interval-patterns"
        }
      , TechRadar.Recommendation::{ language = Schema.Language.Haskell
        , category = TechRadar.Category.Cryptography
        , package = "botan"
        , level = TechRadar.AdoptionLevel.Assess
        , reason = Some
            "Haskell bindings to the Botan C++ cryptography library; broader algorithm coverage than crypton. Evaluate against current crypton-based usage."
        }
      ]
    }
