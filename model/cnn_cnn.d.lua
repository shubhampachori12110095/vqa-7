require 'nn'
require 'nngraph'
require 'module/sentenceCNN'

local question = nn.Identity()()
local image = nn.Identity()()
local emb_question = nn.LookupTable(857, 10)(question)
local se = sentenceCNN(10, {{3,1,50,2,2},
			    {3,1,100,2,2},
			    {3,1,100,2,2}})(emb_question)
local word1, word2 = nn.SplitTable(1, 2)(se):split(2)
local iword = nn.Linear(1000,100)(image)
local mword = nn.JoinTable(1, 1)({word1, iword, word2})
local prob = nn.LogSoftMax()(nn.Linear(3*100, 969)(mword))

return nn.gModule({image, question},{prob})
