//
// Copyright (c) 2023, Brian Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   8 Aug 2023  Brian Frank  Creation
//

using concurrent
using util
using xeto
using haystack::Marker
using haystack::NA
using haystack::Remove
using haystack::Ref
using haystack::Dict

**
** Reader for Xeto binary encoding of specs and data
**
** NOTE: this encoding is not backward/forward compatible - it only
** works with XetoBinaryWriter of the same version
**
@Js
class XetoBinaryReader : XetoBinaryConst, NameDictReader
{

//////////////////////////////////////////////////////////////////////////
// Constructor
//////////////////////////////////////////////////////////////////////////

  new make(XetoTransport transport, InStream in)
  {
    this.transport = transport
    this.names = transport.names
    this.maxNameCode = transport.maxNameCode
    this.in = in
  }

//////////////////////////////////////////////////////////////////////////
// Remote Env Bootstrap
//////////////////////////////////////////////////////////////////////////

  RemoteEnv readBoot()
  {
    if (transport.envRef != null) throw Err("Already booted")

    verifyU4(magic, "magic")
    verifyU4(version, "version")
    readNameTable
    registry := readRegistry
    return RemoteEnv(names, registry) |env|
    {
      XetoTransport#envRef->setConst(transport, env)
      sys := readLib
      registry.map["sys"].set(sys)
      verifyU4(magicEnd, "magicEnd")
    }
  }

  private Void readNameTable()
  {
    max := readVarInt
    for (i := NameTable.initSize+1; i<=max; ++i)
      names.add(in.readUtf)
  }

  private RemoteRegistry readRegistry()
  {
    acc := RemoteRegistryEntry[,]
    while (true)
    {
      nameCode := readVarInt
      if (nameCode == 0) break
      entry := readRegistryEntry(nameCode)
      acc.add(entry)
    }

    return RemoteRegistry(transport, acc)
  }

  private RemoteRegistryEntry readRegistryEntry(Int nameCode)
  {
    name := names.toName(nameCode)

    dependsSize := readVarInt
    depends := Str[,]
    depends.capacity = dependsSize
    dependsSize.times { depends.add(names.toName(readName)) }

    return RemoteRegistryEntry(name, depends)
  }

//////////////////////////////////////////////////////////////////////////
// Lib
//////////////////////////////////////////////////////////////////////////

  XetoLib readLib()
  {
    lib := XetoLib()

    verifyU4(magicLib, "magicLib")
    nameCode  := readName
    meta      := readMeta
    loader    := RemoteLoader(transport.env, nameCode, meta)
    readTypes(loader)
    verifyU4(magicLibEnd, "magicLibEnd")

    return loader.loadLib
  }

  private Void readTypes(RemoteLoader loader)
  {
    while (true)
    {
      nameCode := readName
      if (nameCode < 0) break
      x := loader.addType(nameCode)
      readSpec(loader, x)
    }
  }

  private Void readSpec(RemoteLoader loader, RSpec x)
  {
    x.baseIn  = readSpecRef
    x.typeIn  = readSpecRef
    x.metaIn  = ((MNameDict)readMeta).wrapped
    x.slotsIn = readSlots(loader, x)
    x.flags   = readVarInt
   }

  private RSpec[]? readSlots(RemoteLoader loader, RSpec parent)
  {
    size := readVarInt
    if (size == 0) return null
    acc := RSpec[,]
    acc.capacity = size
    size.times
    {
      name := readName
      x := loader.makeSlot(parent, name)
      readSpec(loader, x)
      acc.add(x)
    }
    return acc
  }

  private RSpecRef? readSpecRef()
  {
    // first byte is slot path depth:
    //  - 0: null
    //  - 1: top-level type like "foo::Bar"
    //  - 2: slot under type like "foo::Bar.baz"
    //  - 3: "foo::Bar.baz.qux"

    depth := read
    if (depth == 0) return null

    lib  := readName
    type := readName
    slot := 0
    Int[]? more := null
    if (depth > 1)
    {
      slot = readName
      if (depth > 2)
      {
        moreSize := depth - 2
        more = Int[,]
        more.capacity = moreSize
        moreSize.times { more.add(readName) }
      }
    }

    return RSpecRef(lib, type, slot, more)
  }

//////////////////////////////////////////////////////////////////////////
// Values
//////////////////////////////////////////////////////////////////////////

  Dict readDict()
  {
    val := readVal
    if (val is Dict) return val
    throw IOErr("Expecting dict, not $val.typeof")
  }

  override Obj readVal()
  {
    ctrl := in.readU1
    switch (ctrl)
    {
      case ctrlMarker:      return Marker.val
      case ctrlNA:          return NA.val
      case ctrlRemove:      return Remove.val
      case ctrlTrue:        return true
      case ctrlFalse:       return false
      case ctrlName:        return names.toName(readName)
      case ctrlStr:         return readUtf
      case ctrlUri:         return readUri
      case ctrlRef:         return readRef
      case ctrlDate:        return readDate
      case ctrlTime:        return readTime
      case ctrlDateTimeI4:  return readDateTimeI4
      case ctrlDateTimeI8:  return readDateTimeI8
      case ctrlEmptyDict:   return NameDict.empty
      case ctrlNameDict:    return readNameDict
      case ctrlGenericDict: return readGenericDict
      case ctrlSpecRef:     return readSpecRef // resolve to Spec later
      default:              throw IOErr("obj ctrl 0x$ctrl.toHex")
    }
  }

  private Uri readUri()
  {
    Uri.fromStr(readUtf)
  }

  private Ref readRef()
  {
    Ref.make(readUtf, null)
  }

  private Date readDate()
  {
    Date(in.readU2, Month.vals[in.read-1], in.read)
  }

  private Time readTime()
  {
    Time.fromDuration(Duration(in.readU4 * 1ms.ticks))
  }

  private DateTime readDateTimeI4()
  {
    DateTime.makeTicks(in.readS4*1sec.ticks, readTimeZone)
  }

  private DateTime readDateTimeI8()
  {
    DateTime.makeTicks(in.readS8, readTimeZone)
  }

  private TimeZone readTimeZone()
  {
    TimeZone.fromStr(readVal)
  }

  private MNameDict readNameDict()
  {
    size := readVarInt
    spec := null
    return MNameDict(names.readDict(size, this, spec))
  }

  private Dict readGenericDict()
  {
    acc := Str:Obj[:]
    while (true)
    {
      name := readVal.toStr
      if (name.isEmpty) break
      acc[name] = readVal
    }
    return haystack::Etc.dictFromMap(acc)
  }

  override Int readName()
  {
    code := readVarInt
    if (code != 0) return code

    code = readVarInt
    name := readUtf
    names.set(code, name) // is now sparse
    return code
  }

//////////////////////////////////////////////////////////////////////////
// Utils
//////////////////////////////////////////////////////////////////////////

  Int read()
  {
    in.readU1
  }

  Int readU4()
  {
    in.readU4
  }

  Str readUtf()
  {
    in.readUtf
  }

  Ref[] readRawRefList()
  {
    size := readVarInt
    acc := Ref[,]
    acc.capacity = size
    size.times { acc.add(Ref(readUtf)) }
    return acc
  }

  Dict[] readRawDictList()
  {
    size := readVarInt
    acc := Dict[,]
    acc.capacity = size
    size.times { acc.add(readDict) }
    return acc
  }

  private Dict readMeta()
  {
    verifyU1(ctrlNameDict, "ctrlNameDict for meta")  // readMeta is **with** the ctrl code
    return readNameDict
  }

  private Void verifyU1(Int expect, Str msg)
  {
    actual := in.readU1
    if (actual != expect) throw IOErr("Invalid $msg: 0x$actual.toHex != 0x$expect.toHex")
  }

  private Void verifyU4(Int expect, Str msg)
  {
    actual := readU4
    if (actual != expect) throw IOErr("Invalid $msg: 0x$actual.toHex != 0x$expect.toHex")
  }

  Int readVarInt()
  {
    v := in.readU1
    if (v == 0xff)           return -1
    if (v.and(0x80) == 0)    return v
    if (v.and(0xc0) == 0x80) return v.and(0x3f).shiftl(8).or(in.readU1)
    if (v.and(0xe0) == 0xc0) return v.and(0x1f).shiftl(8).or(in.readU1).shiftl(16).or(in.readU2)
    return in.readS8
  }

//////////////////////////////////////////////////////////////////////////
// Fields
//////////////////////////////////////////////////////////////////////////

  private const XetoTransport transport
  private const NameTable names
  private const Int maxNameCode
  private InStream in
}


