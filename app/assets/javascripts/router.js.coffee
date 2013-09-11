# For more information see: http://emberjs.com/guides/routing/
App.Router.map ->
  @resource 'about'
  @resource 'appliance_types', ->
    @resource 'appliance_type', path: ':appliance_type_id'
    @route 'new'
  @resource 'users', ->
    @resource 'user', path: ':user_id'
    @route 'new'
  @resource 'security_proxies', ->
    @resource 'security_proxy', path: ':security_proxy_id'
    @route 'new'
  @resource 'security_policies', ->
    @resource 'security_policy', path: ':security_policy_id'
    @route 'new'
  @resource 'profile'