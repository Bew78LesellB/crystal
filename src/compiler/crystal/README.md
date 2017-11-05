Seems like when the toplevelvisitor:
- traverse a lib, it creates a LibType, store it in the scope's types, but don't keep a reference to the LibDef.
- traverse a FunDef in a lib, it creates an External, attach it to the FunDef, but don't attach the external to the LibType, so I can't access them from the LibType
