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

**
** Transport for I/O of Xeto specs and data across network.
** This is the base class for XetoClient and XetoServer.
**
@Js
const class XetoTransport
{
  ** Constructor to wrap given local environment
  new makeServer(MEnv env)
  {
    this.envRef = env
    this.names = env.names
    this.maxNameCode = names.maxCode
  }

  ** Constructor to load RemoteEnv
  new makeClient()
  {
    this.envRef = null             // set in XetoBinaryReader.readBoot
    this.names = NameTable()       // start off with empty name table
    this.maxNameCode = Int.defVal  // can safely use every name mapped from server
  }

  ** Environment for the transport
  MEnv env() { envRef }
  internal const MEnv? envRef

  ** Shared name table up to maxNameCode
  const NameTable names

  ** Max name code (inclusive) that safe to use
  const Int maxNameCode

  ** Asynchronously load a library
  virtual Void loadLib(Str qname, |Err?, Lib?| f)
  {
    throw UnsupportedErr()
  }

}