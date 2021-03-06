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
    belongs_to :user,
               class_name: 'Atmosphere::User'

    belongs_to :fund,
               class_name: 'Atmosphere::Fund'

    validates :user_id,
              uniqueness: {
                scope: :fund_id,
                message: I18n.t('funds.unique_user')
              }

    around_save :ensure_single_default
    after_destroy :reallocate_default,
                  if: Proc.new { |user_fund| user_fund.default }

    private

    def ensure_single_default
      unless default
        ufs = UserFund.where(user_id: user_id)
        if ufs.count == 0 || (ufs.count == 1 && ufs[0].id == id)
          self.default = true
        end
      end

      yield

      if default
        ufs = UserFund.where(user_id: user_id, default: true)
        (ufs - [self]).each do |uf|
          uf.update_attributes(default: false)
        end
      end
    end

    def reallocate_default
      uf = UserFund.find_by(user_id: user_id)
      uf && uf.update_attributes(default: true)
    end
  end
end
