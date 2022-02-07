//
// Copyright (c) 2022, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   02 Feb 2022  Matthew Giannini  Creation
//

using haystack
using hxConn

internal class EcobeeLearn : EcobeeConnTask, EcobeeUtil
{

//////////////////////////////////////////////////////////////////////////
// Constructor
//////////////////////////////////////////////////////////////////////////

  new make(EcobeeDispatch dispatch, Obj? arg) : super(dispatch)
  {
    this.arg = arg
  }

  private Obj? arg

//////////////////////////////////////////////////////////////////////////
// Learn
//////////////////////////////////////////////////////////////////////////

  Grid learn() { run }

  override Obj? run()
  {
    t1 := Duration.now
    try
    {
      openPin
      meta := ["ecobeeConnRef": conn.id]
      rows := Dict[,]
      if (arg == null) rows = learnRoot
      else rows = (Dict[])arg
      return Etc.makeDictsGrid(meta, rows)
    }
    finally
    {
      closePin
      t2 := Duration.now
      if (arg == null) log.info("${conn.dis} Learn ${arg} [${(t2-t1).toLocale}]")
    }
  }

  private Dict[] learnRoot()
  {
    acc := Dict[,]

    thermostats := client.thermostat.get(EcobeeSelection {
      it.selectionType  = SelectionType.registered
      it.includeRuntime = true
      it.includeSensors = true
    })

    thermostats.each |thermostat|
    {
      tags := Str:Obj?[
        "id": Ref(thermostat.id),
        "dis": thermostat.name,
        "ecobeeModelNumber": thermostat.modelNumber,
        "equip": Marker.val,
        "thermostat": Marker.val,
      ]

      // learn children now since we have the data already
      children := learnRemoteSensors(thermostat)
      children.addAll(learnThermostatPoints(thermostat))
      tags["learn"] = children

      acc.add(Etc.makeDict(tags))
    }

    return acc
  }

  private Dict[] learnRemoteSensors(EcobeeThermostat thermostat)
  {
    acc := Dict[,]
    thermostat.remoteSensors.each |sensor|
    {
      tags := Str:Obj?[
        "id": Ref(sensor.id),
        "dis": "• ${sensor.name} (Remote Sensor)",
        "ecobeeSensorType": sensor.type,
        "equip": Marker.val,
        "thermostat": Marker.val,
      ]

      // learn children now since we have the data already
      children := learnRemoteSensorPoints(thermostat, sensor)
      tags["learn"] = children

      acc.add(Etc.makeDict(tags))
    }

    return acc
  }

  private Dict[] learnThermostatPoints(EcobeeThermostat t)
  {
    points := Dict[,]

    points.add(PointBuilder(t).dis("Actual Temperature").kind("Number").unit(fahr)
      .markers("zone,air,temp,sensor").cur("runtime/actualTemperature", "/ 10").finish)

    points.add(PointBuilder(t).dis("Actual Humidity").kind("Number").unit(relHum)
      .markers("zone,air,humidity,sensor").cur("runtime/actualHumidity").finish)

    points.add(PointBuilder(t).dis("Raw Temperature").kind("Number").unit(fahr)
      .markers("zone,air,temp,sensor").cur("runtime/rawTemperature", "/ 10").finish)

    points.add(PointBuilder(t).dis("Desired Heat").kind("Number").unit(fahr)
      .markers("zone,air,temp,heating,sp").cur("runtime/desiredHeat", "/ 10").finish)

    points.add(PointBuilder(t).dis("Desired Cool").kind("Number").unit(fahr)
      .markers("zone,air,temp,cooling,sp").cur("runtime/desiredCool", "/ 10").finish)

    points.add(PointBuilder(t).dis("Desired Humidity").kind("Number").unit(relHum)
      .markers("zone,air,humidity,sp").cur("runtime/desiredHumidity").finish)

    // TODO: actualVOC???

    points.add(PointBuilder(t).dis("Actual CO2").kind("Number")
      .markers("zone,air,co2,sensor").cur("runtime/actualCO2").finish)

    // TODO: AQAccuracy/Score???
    return points
  }

  private Dict[] learnRemoteSensorPoints(EcobeeThermostat t, EcobeeRemoteSensor s)
  {
    // TODO: adc, dryContact
    points := Dict[,]

    if (s.hasCapability("co2"))
    {
      points.add(PointBuilder(t).dis("CO2").kind("Number")
        .markers("zone,air,co2,sensor").cur(capProp(s, "co2"), "strToNumber").finish)
    }
    if (s.hasCapability("humidity"))
    {
      points.add(PointBuilder(t).dis("Humidity").kind("Number").unit(relHum)
        .markers("zone,air,humidity,sensor").cur(capProp(s, "humidity"), "strToNumber").finish)
    }
    if (s.hasCapability("temperature"))
    {
      points.add(PointBuilder(t).dis("Temp").kind("Number").unit(fahr)
        .markers("zone,air,temp,sensor").cur(capProp(s, "temperature"), "strToNumber / 10").finish)
    }
    // if (s.hasCapability("occupancy"))
    // {
    //   points.add(PointBuilder(t).dis("Occupancy").kind("Bool")
    //     .markers("zone,occupied,sensor").cur(capProp(s, "occupancy"), "strToBool").finish)
    // }
    return points
  }

  ** Convenience to build the path for a remote sensor capability
  private static Str capProp(EcobeeRemoteSensor s, Str type)
  {
    "remoteSensors[${s.id}]/capability[type=${type}]/value"
  }
}

**************************************************************************
** PointBuilder
**************************************************************************

internal class PointBuilder
{
  new make(EcobeeThermostat thermostat)
  {
    this.thermostat = thermostat
    this.tags = Str:Obj?[
      "point": Marker.val,
      "ecobeePoint": Marker.val,
    ]
  }

  private EcobeeThermostat thermostat
  private Str:Obj tags

  private This set(Str tag, Obj? val) { tags[tag] = val; return this }

  This dis(Str dis) { set("dis", dis) }
  This kind(Str kind) { set("kind", kind) }
  This unit(Unit unit) { set("unit", unit.toStr) }
  This cur(Str path, Str? convert := null)
  {
    set("ecobeeCur", "${thermostat.id}/${path}")
    if (convert != null) set("curConvert", convert)
    return this
  }
  This write(Str path, Str? convert := null)
  {
    set("ecobeeWrite", "${thermostat.id}/${path}")
    if (convert != null) set("writeConvert", convert)
    return this
  }
  This curAndWrite(Str path) { cur(path).write(path) }
  This enums(Str enums) { set("enum", enums) }
  This markers(Str markers)
  {
    markers.split(',').each |marker| { tags[marker] = Marker.val }
    return this
  }

  Dict finish() { Etc.makeDict(tags) }
}