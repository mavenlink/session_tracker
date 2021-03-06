require 'spec_helper'

describe SessionTracker, "track" do
  let(:redis) { mock.as_null_object }

  it "should store the user in a set for the current minute" do
    time = Time.parse("15:04")
    redis.should_receive(:sadd).with("active_customer_sessions_minute_04", "abc123")
    tracker = SessionTracker.new("customer", :redis => redis)
    tracker.track("abc123", time)
  end

  it "should expire the set within an hour to prevent it wrapping around" do
    time = Time.parse("15:59")
    redis.should_receive(:expire).with("active_customer_sessions_minute_59", 60 * 59)
    tracker = SessionTracker.new("customer", :redis => redis)
    tracker.track("abc123", time)
  end

  it "should be able to track different types of sessions" do
    time = Time.parse("15:04")
    redis.should_receive(:sadd).with("active_employee_sessions_minute_04", "abc456")
    tracker = SessionTracker.new("employee", :redis => redis)
    tracker.track("abc456", time)
  end

  it "should do nothing if the session id is nil" do
    redis.should_not_receive(:sadd)
    redis.should_not_receive(:expire)
    tracker = SessionTracker.new("employee", :redis => redis)
    tracker.track(nil)
  end

  it "should accept either options or a Redis object as the second argument" do
    time = Time.parse("15:04")
    redis.should_receive(:sadd).with("active_employee_sessions_minute_04", "abc456")
    tracker = SessionTracker.new("employee", redis)
    tracker.track("abc456", time)
  end

  it "should not raise any errors by default" do
    redis.should_receive(:expire).and_raise('fail')
    tracker = SessionTracker.new("customer", :redis => redis)
    lambda { tracker.track("abc123", Time.now) }.should_not raise_error
  end

  it "should raise errors if requested" do
    redis.should_receive(:expire).and_raise('fail')
    tracker = SessionTracker.new("customer", :redis => redis, :propagate_exceptions => true)
    lambda { tracker.track("abc123", Time.now) }.should raise_error(/fail/)
  end
end

describe SessionTracker, "active_users" do
  let(:redis) { mock.as_null_object }

  it "should do a union on the specified timespan to get a active user count" do
    time = Time.parse("13:09")
    redis.should_receive(:sunion).with("active_customer_sessions_minute_09",
                                       "active_customer_sessions_minute_08",
                                       "active_customer_sessions_minute_07").
                                       and_return([ mock, mock ])

    SessionTracker.new("customer", redis).active_users(3, time).should == 2
  end

  it "should use a default time span of 5 minutes" do
    redis.should_receive(:sunion).with(anything, anything, anything,
                                       anything, anything).and_return([ mock, mock ])

    SessionTracker.new("customer", redis).active_users.should == 2
  end

  it "should be possible to access the data" do
    redis.should_receive(:sunion).and_return([ :d1, :d2 ])
    SessionTracker.new("customer", redis).active_users_data(3, Time.now).should == [ :d1, :d2 ]
  end
end

describe SessionTracker, "active_friends" do
  let(:redis) { mock.as_null_object }

  it "should do a union on the specified timespan, store it, intersect it with a friends key, and then cleanup" do
    time = Time.parse("13:09")
    session_tracker = SessionTracker.new("customer", redis)
    session_tracker.should_receive(:random_key).and_return("tmp_key")
    redis.should_receive(:sunionstore).with("tmp_key",
                                            "active_customer_sessions_minute_09",
                                            "active_customer_sessions_minute_08",
                                            "active_customer_sessions_minute_07").
                                            and_return([ mock, mock ])
    redis.should_receive(:sinter).with("tmp_key", "some_friend_key").and_return(["2", "4"])
    redis.should_receive(:del).with("tmp_key")

    session_tracker.active_friends("some_friend_key", :timespan_in_minutes => 3, :time => time).should == ["2", "4"]
  end
end

describe SessionTracker, "untrack" do
  let(:redis) { mock.as_null_object }

  it "should remove the specfied session id from recent buckets" do
    time = Time.parse("13:09")
    redis.should_receive(:srem).with("active_customer_sessions_minute_09", 123)
    redis.should_receive(:srem).with("active_customer_sessions_minute_08", 123)
    redis.should_receive(:srem).with("active_customer_sessions_minute_07", 123)
    redis.should_not_receive(:srem).with("active_customer_sessions_minute_06", 123)
    SessionTracker.new("customer", redis).untrack(123, 3, time)
  end
end
