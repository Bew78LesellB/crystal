Seems like when the TopLevelVisitor:
- traverse a lib, it creates a LibType, store it in the scope's types, but don't keep a reference to the LibDef.
- traverse a FunDef in a lib, it creates an External, attach the FunDef to it, but don't attach the external to the LibType, so I can't access them from the LibType

YESSS!! I got it working, by adding manually the External to the LibType's defs!!




When the TopLevelVisitor traverse a CStructOrUnionDef, it creates a NonGenericClassType
I'm trying to make a CStructOrUnionTypeNode (fictious node for macros), inheriting from TypeNode, but having a special macro method `fields` to gets the fields of the struct

====> I got this working (the inheritance), but now (as expected?) the CStructOrUnionTypeNode also has all macro methods of TypeNode.. (maybe later TypeNode should be stripped from some macro methods?)





Ultimately, later, the `TypeNode` won't have all macro methods for all types, but there will be a hierarchy of fictitious TypeNode for each types we want to handle to the macro system.



#### Expose lib's structs/unions content to the macro system

Looks like this will be HARD to get the C-struct's fields from macros, as currently when the TopLevelVisitor traverse a CStructOrUnionDef it only creates the container of the type, not the fields inside. We need to wait for the TypeDeclarationProcessor to analyse the `var : Type` things.

I think that lib types can be a special case, because C-structs/unions/enums can't be re-opened, so we should be able to process their type declarations during TopLevelVisitor ?

=====> Do we want to do that?




#### Workflow when looking at lib types

So now we have:
- `TopLevelVisitor` creates `Type`s of everything (top level only though)
- when the `MacroInterpreter` resolves a `Path`, if it's a `LibType`, wrap it in a `LibTypeNode` (which inherits from `TypeNode` & by extension from `ASTNode`) and return it
- when calling `LibTypeNode#types`, find the types in `LibType`:
  * if it looks like a C-struct/union, wrap it in a `CStructOrUnionTypeNode`
  * if it's a `EnumType`, wrap it in a `EnumTypeNode`


`LibTypeNode`, `CStructOrUnionTypeNode`, `EnumTypeNode` are macro's astnode-like classes with macro methods on them, used to manipulate the `Type`s.
