require "modules/substitution.k"

module JS-SYNTAX
  syntax Ref ::= Int
  syntax Refs ::= List{Ref,","}

  syntax Value ::= Ref
                 | String
                 | "undefined"
                 | "null"
  syntax Values ::= List{Value,","}          [strict]

  syntax Ids ::= List{Id,","}                [strict]

  syntax Block ::= "var" Ids ";" Stmt

  syntax Func ::= "function" "(" Ids ")" "{" Block "}" [binder]

  syntax Expr ::= "{" ObjFields "}"          [strict]
                | Expr "[" Expr "]"          [seqstrict]
                | Expr "[" Expr "]" "=" Expr [seqstrict]
                | Id "=" Expr		     [strict(2)]
                | Id			     [strict]
                | Func
                | Expr "(" Values ")"        [seqstrict, left]
                | "print" "(" Expr ")"       [strict]
		| Sets(Refs, String, Value)
		| Gets(Refs, String)
                > "(" Expr ")"               [bracket]
                | Value
                | "with" "(" Expr ")" "{" Stmt "}" [strict(1)] 
  
  syntax Stmt ::= Expr   		     [strict]
                | "return" Expr              [strict]
                > Stmt ";" Stmt              [strict(1), left]

  syntax ObjFields ::= List{ObjField,","}    [seqstrict]
  syntax ObjField ::= String ":" Expr        [strict(2)]
                    | GetterSetter

  syntax GetterSetter ::= Getter | Setter
  syntax Getter ::= "get" String "()" "{" Expr "}"         [strict(2)]
  syntax Setter ::= "set" String "(" Id ")" "{" Expr "}"   [strict(2)]

endmodule

module JS
  imports JS-SYNTAX
  imports SUBSTITUTION

  syntax ScopeObj ::= Scope(Value, Map)

  syntax Lambda ::= "FBegin" Ids "**" Values "**" Stmt  [strict(2)]

  syntax ValObjField ::= String ":" Value
                       | GetterSetter
                 
  syntax ValObjFields ::= List{ValObjField,","}
  syntax ValObj ::= "{" ValObjFields "}"
  syntax ObjMap ::= Obj(Map, MaybeFuncObj)

  // Used to map strings to <getter> ** <setter> pairs
  syntax AccessPair ::= MaybeFun "**" MaybeFun 
  syntax MaybeFun ::= Func
                    | "nofun"

  syntax SetterReturn ::= SetRet(Value)

  syntax RetValue ::= Ref
                    | String
                    
  syntax FuncObj ::= FuncObj(Ref, Ids, Stmt)
  
  syntax MaybeFuncObj ::= FuncObj
                        | "nofunobj"
  
  syntax CurEnv  ::= env(Ref)

  syntax K ::= ObjMap | SetterReturn | "FEnd" Refs
  // syntax K ::= SetterReturn | "FEnd" Refs
  syntax KResult ::= Value | ValObjField | RetValue | "return" RetValue 
                   // | Id "=" Value

  configuration <C>
                    <k> $PGM:Block </k>
                    <Stage> .Map </Stage>
                    <ObjStore> (0 |-> Obj(.Map, nofunobj)) </ObjStore>
                    <Scope> 0, .Refs </Scope>
                    <R> 1 </R>
                    <in stream="stdin"> .List </in>
                    <out stream="stdout"> .List </out>
                </C>

  rule [Val-Sequencing] :
      V:Value ; St:Stmt => St

  /**
   * Objects
   */
  rule [Gets-Got] :
      <k> Gets((R:Ref, _), Str:String) => V ... </k>
      <ObjStore> OS:Map(R |-> Obj(M:Map(Str |-> V:Value), _)) </ObjStore>

  rule [Gets-Miss] :
      <k> Gets((R:Ref, Rs:Refs), Str:String) => Gets(Rs, Str) ...</k>
      <ObjStore> OS:Map(R |-> Obj(M:Map, _)) </ObjStore>
      when notBool $hasField(M, Str)

  rule [Object-Intro]:
       <k> ( { O:ValObjFields } => O ~> Obj(M, nofunobj) ) ... </k>
       <Stage> M:Map => .Map </Stage>

  rule [Property-Intro]:
        <k> ( Str:String : V:Value, O:ValObjFields => O) ... </k>
       <Stage> M:Map => M[V / Str] </Stage> 

  rule [Reference-Object]:
       <k> ( .ValObjFields ~> Obj(Old:Map, nofunobj) => R ) ... </k>
       <Stage> M:Map => Old </Stage>
       <ObjStore> OS:Map(. => R |-> Obj(M, nofunobj) ) </ObjStore>
       <R> R:Ref => R +Int 1 </R> 

  rule [E-GetField] :
       <k> ( R:Ref [ Str : String ] => V ) ... </k>
       <ObjStore> OS:Map( R |-> Obj(O:Map(Str |-> V:Value), _)) </ObjStore>
       
  rule [E-NoField] :
       <k> ( R:Ref [ Str : String ] => undefined) ... </k>
       <ObjStore> OS:Map( R |-> Obj(O, _)) </ObjStore>
       when notBool(Str in keys(O))

  rule [E-SetField] :
       <k> ( R:Ref [Str:String] = V:Value => V ) ... </k>
       <ObjStore> OS:Map(R |-> Obj(M:Map => M[V / Str], _)) </ObjStore>

  /**
   * Getters
   */

  rule [Getter-Update]:
       <k> (get S:String () { E:Expr }, O:ValObjFields => O) ... </k>
       <Stage> M:Map(S |-> (F1 => E) ** F2) </Stage>

  rule [Getter-Intro]:
       <k> (get S:String () { E:Expr }, O:ValObjFields => O) ... </k>
       <Stage> M:Map(. => S |-> E ** nofun) </Stage>
       when notBool(S in keys(M))

  rule [E-Getter] :
       <k> ( R:Ref [ Str : String ] => E) ... </k>
       <ObjStore> OS:Map(R |-> Obj(O:Map(Str |-> E:Expr ** F), _)) </ObjStore>
  
  /**
   * Setters
   */

  rule [Setter-Update]:
       <k> (set S:String ( I:Id ) { E:Expr }, O:ValObjFields => O) ... </k>
       <Stage> M:Map(S |-> F ** (F1 => ( function (I) { E } ))) </Stage>

  rule [Setter-Intro]:
       <k> (set S:String ( I:Id ) { E:Expr }, O:ValObjFields => O) ... </k>
       <Stage> M:Map(. => S |-> nofun ** ( function (I) { E } )) </Stage>
       when notBool(S in keys(M)) 
                    
  rule [E-Setter] :
       <k> ( R:Ref [Str:String] = V:Value => F(V) ~> SetRet(V)) ... </k>
       <ObjStore> OS:Map(R |-> Obj(M:Map (Str |-> F1 ** F:Func), _)) </ObjStore>
  
  rule [Setter-Return]:
       <k> (V:Value ~> SetRet(V2:Value) => V2) ... </k>

  /**
   * Function Application
   */
  
   
  /**
   * Printing
   */

  rule [Printing] :
       <k> print ( V:Value ) => undefined ... </k>
       <out> ... (. => ListItem(V)) </out>

  /**
   * Variables
   */
  rule [Var-Declaration] :
      <k> var ( X:Id, Rest:Ids => Rest ) ; St:Stmt ... </k>
      <ObjStore> OS:Map(R |-> Obj(M:Map => M[undefined / Id2String(X)], _)) </ObjStore>
      <Scope> R:Ref, _ </Scope>

  rule [Empty-Var] :
      var .Ids ; St:Stmt => St [structural]

  rule [Var-Assignment] :
      <k> X:Id = V:Value => Sets(Rs, Id2String(X), V) ... </k>
      <Scope> Rs:Refs </Scope>

  rule [Var-Lookup] :
      <k> X:Id => Gets(Rs, Id2String(X)) ... </k>
      <Scope> Rs:Refs </Scope>

  rule [With] :
      <k> with (R:Ref) { Rest:Stmt } => Rest </k>
      <Scope> Rs:Refs => R,Rs </Scope>

endmodule
