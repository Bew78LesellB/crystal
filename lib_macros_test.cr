lib LibFoo
  fun fun_no_args_no_return
  fun fun_no_args : Int32
  fun fun_no_return(var : UInt8)
  fun crystal_fun = c_len(str : UInt8*) : Int32

  struct CStruct
    field1 : UInt8
    field2 : Int32
  end

  union CUnion
    int : Int32
    str : UInt8*
  end

  enum CEnum
    Field1
    Field2
  end
end

macro describe_lib(lib_node)
  {% l = lib_node.resolve %}
  {% puts l.class_name %}

  {% funcs = l.functions %}
  {% for func in funcs %}
    {% puts "Fun: #{func.name}(#{func.args.splat})" %}
  {% end %}
  {% puts %}

  {% types = l.types %}
  {% for type in types %}
    {% puts "Type: #{type.name}" %}
    {% puts "  union? #{type.union?}" %}
    {% if type.is_a?(EnumTypeNode) %}
      {% puts "  Enum members:" %}
      {% for member in type.members %}
        {% puts "    * #{member}" %}
      {% end %}
    {% end %}
  {% end %}
  {% puts %}
end


describe_lib LibFoo




