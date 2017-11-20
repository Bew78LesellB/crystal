Seems like when the TopLevelVisitor:
- traverse a lib, it creates a LibType, store it in the scope's types, but don't keep a reference to the LibDef.
- traverse a FunDef in a lib, it creates an External, attach the FunDef to it, but don't attach the external to the LibType, so I can't access them from the LibType

YESSS!! I got it working, by manually adding the External to the LibType's defs!!

Note: the External (the Type) has a reference to the FunDef, but for most others Type, there's no reference to its corresponding ASTNode.




When the TopLevelVisitor traverse a CStructOrUnionDef, it creates a NonGenericClassType
I'm trying to make a CStructOrUnionTypeNode (fictious node for macros), inheriting from TypeNode, but having a special macro method `fields` to gets the fields of the struct

====> I got this working (the inheritance), but now (as expected?) the CStructOrUnionTypeNode also has all macro methods of TypeNode..
(maybe later TypeNode should be stripped from some macro methods?)





Ultimately, later, the `TypeNode` won't have all macro methods for all types, but there will be a hierarchy of fictitious TypeNode for each types we want to handle in the macro system.



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




#### Explaination for my issue



As far as I understand, the `TopLevelVisitor` traverses everything (top-level only) and build the `Type`s and store them in the current scope when needed.
In the process, the `ASTNode` is lost, no reference to it is saved in the generated `Type` (or I didn't find where).

For example for a `lib` node, the `ASTNode` is `LibDef`, and the generated `Type` is `LibType`, see here:
https://github.com/crystal-lang/crystal/blob/3e6804399f2a5f6a00c83ce40c0e234eb045ab63/src/compiler/crystal/semantic/top_level_visitor.cr#L386-L413

For a C-`struct` or `union`, the `ASTNode` is `CStructOrUnionDef`, and the generated `Type` is `NonGenericClassType`, see here:
https://github.com/crystal-lang/crystal/blob/3e6804399f2a5f6a00c83ce40c0e234eb045ab63/src/compiler/crystal/semantic/top_level_visitor.cr#L415-L444


When the `MacroInterpreter` sees a path (like `Foo::LibBar` or `Array`) (or when we use `#resolve?`), it tries to resolve it's type, by looking in the current scope, searching for the `Type` associated with this path, which is then returned to the interpreter.
And when we try to invoke a macro method, it'll call `interpret` on it.



