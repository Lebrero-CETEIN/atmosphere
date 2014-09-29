# == Schema Information
#
# Table name: user_funds
#
#  id      :integer          not null, primary key
#  user_id :integer
#  fund_id :integer
#  default :boolean          default(FALSE)
#

# Linking table between Users and Funds
module Atmosphere
  class UserFund < ActiveRecord::Base
    self.table_name = 'user_funds'

    belongs_to :user
    belongs_to :fund
  end
end
