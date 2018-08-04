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

  # Chrono refiner that will apply time zone offset implied by options.
  #
  # Time zone offset should be assigned instead of implied because system time
  # zone takes precedence to implied time zone.
  assignTimeZoneOffsetRefiner = new chrono.Refiner()
  assignTimeZoneOffsetRefiner.refine = (text, results, opt) ->
    return results unless opt['timezoneOffset']?

    results.forEach (result) ->
      unless result.start.isCertain('timezoneOffset')
        result.start.assign 'timezoneOffset', opt['timezoneOffset']

      if result.end? and not result.end.isCertain('timezoneOffset')
        result.end.assign 'timezoneOffset', opt['timezoneOffset']

    results

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
    referenceDate = moment.tz(userTimeZone?.tz)
    messageDate   = chrono.custom.parseDate res.message.text, referenceDate, timezoneOffset: referenceDate.utcOffset()

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
