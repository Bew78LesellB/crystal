Seems like when the TopLevelVisitor:
- traverse a lib, it creates a LibType, store it in the scope's types, but don't keep a reference to the LibDef.
- traverse a FunDef in a lib, it creates an External, attach the FunDef to it, but don't attach the external to the LibType, so I can't access them from the LibType

YESSS!! I got it working, by adding manually the External to the LibType's defs!!


When the TopLevelVisitor traverse a CStructOrUnionDef, it creates a NonGenericClassType
I'm trying to make a CStructOrUnionTypeNode (fictious node for macros), inheriting from TypeNode, but having a special macro method `fields` to gets the fields of the struct





Ultimately, later, the `TypeNode` won't have all macro methods for all types, but there will be a hierarchy of fictitious TypeNode for each types we want to handle to the macro system.




Looks like this will be HARD to get the C-struct's fields from macros, as currently when the TopLevelVisitor traverse a CStructOrUnionDef it only creates the 'coquille' of the type, not the fields. We need to wait for the TypeDeclarationProcessor to analyse the `var : Type` things.


