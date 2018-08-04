# Description
#   Enable hubot to convert times in user time zones during discussion.
#
# Configuration:
#   HUBOT_TIMEZONE_CONVERTER_FORMAT - Moment.js compatible format of response.
#
# Commands:
#   <time expression> - Sends the time converted to all room users time zones.
#
# Notes:
#   It requires a time zone aware adapter and currently it supports only Slack.
#
# Author:
#   Nikolaos Anastopoulos <ebababi@ebababi.net>

moment = require 'moment-timezone'
chrono = require 'chrono-node'

HUBOT_TIMEZONE_CONVERTER_REGEX  = /(?:(?:[1-9]|1[0-2])\s*[ap]m|(?:1?\d|2[0-3])\:[0-5]\d)/i
HUBOT_TIMEZONE_CONVERTER_FORMAT = process.env.HUBOT_TIMEZONE_CONVERTER_FORMAT or "HH:mm [({tz_label})][\n]"

# Custom Chrono instance, enriched with time zone offset assignment refiner.
chrono.custom = do ->
  custom = new chrono.Chrono()

  # Chrono refiner that will imply time zone offset set by options.
  #
  # This requires `chrono-node` version 1.3.7 and it doesn't have any effect in
  # lesser versions.
  implyTimeZoneOffsetRefiner = new chrono.Refiner()
  implyTimeZoneOffsetRefiner.refine = (text, results, opt) ->
    return results unless opt['timezoneOffset']?

    results.forEach (result) ->
      result.start.imply 'timezoneOffset', opt['timezoneOffset']
      result.end.imply 'timezoneOffset', opt['timezoneOffset'] if result.end?

    results

  # Converts chrono parsed components to a moment date object with time zone.
  parsedComponentsToMoment = (parsedComponents, zoneName) ->
    dateMoment = moment.tz zoneName

    dateMoment.set 'year', parsedComponents.get('year')
    dateMoment.set 'month', parsedComponents.get('month') - 1
    dateMoment.set 'date', parsedComponents.get('day')
    dateMoment.set 'hour', parsedComponents.get('hour')
    dateMoment.set 'minute', parsedComponents.get('minute')
    dateMoment.set 'second', parsedComponents.get('second')
    dateMoment.set 'millisecond', parsedComponents.get('millisecond')

    dateMoment

  # Chrono refiner that will apply time zone offset implied by options.
  #
  # Time zone offset should be assigned instead of implied because system time
  # zone takes precedence to implied time zone in `chrono-node` versions 1.3.6
  # or less. Moreover,
  assignTimeZoneOffsetRefiner = new chrono.Refiner()
  assignTimeZoneOffsetRefiner.refine = (text, results, opt) ->
    return results unless opt['timezoneName']?

    results.forEach (result) ->
      unless result.start.isCertain('timezoneOffset')
        utcOffset = parsedComponentsToMoment(result.start, opt['timezoneName']).utcOffset()
        result.start.assign 'timezoneOffset', utcOffset

      if result.end? and not result.end.isCertain('timezoneOffset')
        utcOffset = parsedComponentsToMoment(result.end, opt['timezoneName']).utcOffset()
        result.end.assign 'timezoneOffset', utcOffset

    results

  custom.refiners.push implyTimeZoneOffsetRefiner
  custom.refiners.push assignTimeZoneOffsetRefiner
  custom

module.exports = (robot) ->
  # Requires a time zone aware adapter and currently it supports only Slack.
  return unless robot.adapterName is 'slack'

  # Get a time zone hash object given a User object.
  #
  # Returns a time zone hash for the specified user.
  userTimeZoneForUser = (user) ->
    return unless user?.slack?.tz and user.slack.is_bot isnt true
    { tz: user.slack.tz, tz_label: user.slack.tz_label, tz_offset: user.slack.tz_offset } if user?.slack?.tz

  # Get a time zone hash object given a unique user identifier.
  #
  # Returns a time zone hash for the specified user.
  userTimeZoneForID = (id) ->
    userTimeZoneForUser robot.brain.users()[id]

  # Extract an array of unique time zone hash objects of member users given a
  # Channel object.
  #
  # Returns an array of time zone hashes for the specified channel.
  channelTimeZonesForChannel = (channel) ->
    return unless channel?.members or channel?.user
    (channel.members or [channel.user])
      .map (id) ->
        userTimeZoneForID id
      .filter (o) ->
        o?
      .sort (a, b) ->
        a.tz_offset - b.tz_offset
      .reduce \
        (uniq, tz) ->
          uniq.push tz unless tz.tz_label in uniq.map (tz) -> tz.tz_label
          uniq
      , []

  # Command: <time expression> - Sends the time converted to all room users time zones.
  robot.hear HUBOT_TIMEZONE_CONVERTER_REGEX, (res) ->
    return if res.message.subtype?

    userTimeZone  = userTimeZoneForUser res.message.user
    referenceDate = moment.tz userTimeZone?.tz
    referenceZone = moment.tz.zone userTimeZone?.tz
    messageDate   = chrono.custom.parseDate res.message.text, referenceDate,
      timezoneOffset: referenceDate.utcOffset(), timezoneName: referenceZone?.name

    if messageDate
      robot.adapter.client.fetchConversation(res.message.room)
        .then (channel) ->
          roomTimeZones = channelTimeZonesForChannel channel

          if roomTimeZones.length > 1 or channel.is_im
            memberDates = for roomTimeZone in roomTimeZones
              moment.tz(messageDate, roomTimeZone.tz)
                .format HUBOT_TIMEZONE_CONVERTER_FORMAT.replace /\{(\w+)\}/g, (match, property) ->
                  roomTimeZone[property] or match

            res.send memberDates.join ''
