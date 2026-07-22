let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/a3c59033a08c2eaef2cfba4a3c99fc9c192ca6d7/package.dhall
        sha256:18258ef583580a897f4af3e7c86db0342afb42fb40efc535b217ba1089230141

let TechRadar =
      https://raw.githubusercontent.com/shinzui/mori-schema/a3c59033a08c2eaef2cfba4a3c99fc9c192ca6d7/extensions/tech-radar/package.dhall
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
