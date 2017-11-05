lib LibFoo
  fun fun_no_args_no_return
  fun fun_no_args : Int32
  fun fun_no_return(var : UInt8)
  fun crystal_fun = c_len(str : UInt8*) : Int32
end

macro describe_lib(lib_node)
  {% l = lib_node.resolve %}
  {% puts l.class_name %}
  {% puts l.functions %}
end


describe_lib LibFoo




