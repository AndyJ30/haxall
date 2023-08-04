//
// Copyright (c) 2023, Brian Frank
// All Rights Reserved
//
// History:
//   1 Aug 2023  Brian Frank  Creation
//

**
** NameDict implements name/value pairs backed by a NameTable
**
@NoDoc @Js
native final const class NameDict  : Dict
{
  ** Number of name/value pairs in this dict
  Int size()

  ** Just for testing
  @NoDoc Int fixedSize()

  ** Specification of this dict or 'sys::Dict' if generic.
  override Spec spec()

  ** Return if the there are no name/value pairs
  override Bool isEmpty()

  ** Get the 'id' tag as a Ref or raise exception
  Ref id()

  ** Get the value for the given name or 'def' if name not mapped
  @Operator override Obj? get(Str name, Obj? def := null)

  ** Return true if this dictionary contains given name
  override Bool has(Str name)

  ** Return true if this dictionary does not contain given name
  override Bool missing(Str name)

  ** Iterate through the name/value pairs
  override Void each(|Obj val, Str name| f)

  ** Iterate through the name/value pairs until the given
  ** function returns non-null, then break the iteration and
  ** return resulting object.  Return null if function returns
  ** null for every name/value pair.
  override Obj? eachWhile(|Obj val, Str name->Obj?| f)

  ** Get the value mapped by the given name.  If it is not
  ** mapped to a non-null value, then throw an UnknownNameErr.
  override Obj? trap(Str name, Obj?[]? args := null)
}