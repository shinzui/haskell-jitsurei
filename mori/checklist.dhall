let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/a3c59033a08c2eaef2cfba4a3c99fc9c192ca6d7/package.dhall
        sha256:18258ef583580a897f4af3e7c86db0342afb42fb40efc535b217ba1089230141

let Checklist =
      https://raw.githubusercontent.com/shinzui/mori-schema/a3c59033a08c2eaef2cfba4a3c99fc9c192ca6d7/extensions/checklist/package.dhall
        sha256:cc05b20c0e2111afb61040f4932878e1166cc4693203796eea904d8dc9116270

in  Checklist.ChecklistCatalog::{
    , entries =
      [ Checklist.Checklist::{
        , key = "adopt-haskell-conventions"
        , title = "Adopt Haskell project conventions"
        , category = Checklist.Category.Other "Project setup"
        , description = Some
            "Early choices that prevent expensive convention refactors later."
        , sourceDoc = Some (Schema.DocLocation.LocalFile "core/standards.md")
        , tags = [ "haskell", "setup", "standards", "conventions" ]
        , items =
          [ Checklist.ChecklistItem::{
            , key = "ghc-version"
            , title = "Use GHC 9.12 or newer"
            , kind = Checklist.StepKind.Manual
            , successCriteria = Some
                "The cabal file and local toolchain target GHC 9.12+."
            }
          , Checklist.ChecklistItem::{
            , key = "common-stanza"
            , title = "Define the shared Cabal baseline"
            , kind = Checklist.StepKind.Manual
            , successCriteria = Some
                "`common common` sets `default-language: GHC2024` and the mandatory default extensions."
            , preconditions = [ "ghc-version" ]
            }
          , Checklist.ChecklistItem::{
            , key = "import-common"
            , title = "Import the baseline from every stanza"
            , kind = Checklist.StepKind.Verify
            , command = Some
                "grep -nE '^(library|executable|test-suite|benchmark)\\b|^\\s*import:' *.cabal"
            , successCriteria = Some
                "Every library, executable, test-suite, and benchmark stanza imports `common`."
            , preconditions = [ "common-stanza" ]
            }
          , Checklist.ChecklistItem::{
            , key = "project-prelude"
            , title = "Create and expose `<Project>.Prelude`"
            , kind = Checklist.StepKind.Manual
            , successCriteria = Some
                "`src/<Project>/Prelude.hs` exists, `<Project>.Prelude` is exposed, and prelude dependencies such as text, aeson, time, and lens are declared."
            , preconditions = [ "import-common" ]
            }
          , Checklist.ChecklistItem::{
            , key = "package-imports"
            , title = "Keep PackageImports scoped to the prelude"
            , kind = Checklist.StepKind.Manual
            , successCriteria = Some
                "`PackageImports` is enabled with a pragma in the prelude module, not as a global default extension."
            , preconditions = [ "project-prelude" ]
            }
          , Checklist.ChecklistItem::{
            , key = "generic-labels"
            , title = "Keep generic-lens labels local"
            , kind = Checklist.StepKind.Manual
            , successCriteria = Some
                "The prelude does not import `Data.Generics.Labels ()`; modules that use generic-lens labels import it locally."
            , preconditions = [ "project-prelude" ]
            }
          , Checklist.ChecklistItem::{
            , key = "record-shape"
            , title = "Use the record shape conventions from the start"
            , kind = Checklist.StepKind.Manual
            , successCriteria = Some
                "New records use unprefixed strict fields, explicit deriving strategies, and entity ID first for event and command data."
            , preconditions = [ "common-stanza", "generic-labels" ]
            }
          , Checklist.ChecklistItem::{
            , key = "qualified-imports"
            , title = "Use postpositive qualified imports"
            , kind = Checklist.StepKind.Verify
            , command = Some
                "! grep -rnE '^import qualified ' src test app 2>/dev/null"
            , successCriteria = Some
                "Qualified imports use `import X qualified as Y`."
            , preconditions = [ "import-common" ]
            }
          , Checklist.ChecklistItem::{
            , key = "extra-extensions"
            , title = "Add extra default extensions deliberately"
            , kind = Checklist.StepKind.Manual
            , successCriteria = Some
                "Only documented project-wide extensions are added to `common`; file-specific extensions stay local."
            , preconditions = [ "common-stanza" ]
            }
          ]
        }
      ]
    }
