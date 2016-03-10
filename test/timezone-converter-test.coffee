chai = require 'chai'
sinon = require 'sinon'
chai.use require 'sinon-chai'

expect = chai.expect

describe 'timezone-converter', ->
  beforeEach ->
    @robot =
      adapterName: 'slack'
      respond: sinon.spy()
      hear: sinon.spy()

    require('../src/timezone-converter')(@robot)

  it 'registers a hear listener', ->
    expect(@robot.hear).to.have.been.calledWith(/(?:1?[1-9][ap]m|(?:1?\d|2[0-3])\:[0-5]\d)/i)

  context 'robot', ->
    fx = require 'node-fixtures'

    Robot = require 'hubot/src/robot'
    TextMessage = require('hubot/src/message').TextMessage

    robot   = null
    user    = null
    adapter = null

    beforeEach (done) ->
      robot = new Robot null, 'mock-adapter', false

      robot.adapter.on 'connected', ->
        for uid, user of fx.users
          robot.brain.userForId uid, user
        user = robot.brain.users()['1']

        adapter = robot.adapter
        adapter.client =
          getChannelGroupOrDMByName: (name) ->
            return channel for cid, channel of fx.channels when channel.name is name

        robot.adapterName = 'slack'
        require('../src/timezone-converter')(robot)

        done()

      robot.run()

    afterEach ->
      robot.shutdown()
      fx.reset()

    describe 'hear', ->
      it 'sends to room the converted time', (done) ->
        adapter.on 'send', (envelope, strings) ->
          expect(strings[0]).to.eq """
            09:00 (Eastern Standard Time)
            15:00 (Central European Time)
            16:00 (Eastern European Time)\n
          """
          done()

        adapter.receive new TextMessage user, 'Team meeting at 4pm.'

      it 'ignores subtyped messages', (done) ->
        adapter.on 'send', (envelope, strings) -> done()

        msg = new TextMessage user, 'uploaded an image: Pasted image at 2016-03-10, 10:00 AM'
        msg.subtype = 'file_share'

        adapter.receive msg
        done()
