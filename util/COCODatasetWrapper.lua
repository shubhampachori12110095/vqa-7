local util = require 'util/util'

-- wrap the dataset comes from COCOQA.load_data(), adding functions as follows:
-- size(), reset(), next(), cuda()
--
-- arguments:
-- dataset          dataset comes from COCOQA.load_data()
-- imageFeatures    assemble it to dataset.images
-- [disability]     used to some disability model. ='blind' next() return (Q,A);
--                  ='deaf' next() return (V,Q); not given, next() return ({V,Q},A).
-- [cacheFeature]    if not given, don't aeemble dataset.images as a whole and look
--                  up each a time in next().
local function COCODatasetWrapper(dataset, 
                                  imageFeatures, 
                                  disability, 
                                  cacheFeature,
                                  tfidf,
                                  normalize)
    assert(dataset)
    assert(imageFeatures or (disability == 'blind'))
    assert((not disability) or (disability == 'blind') 
            or (disability == 'deaf'))
    assert((not cacheFeature) or (cacheFeature and imageFeatures and 
            type(imageFeatures) ~= 'table'))
    assert((not tfidf) or (tfidf and dataset.tfidfs))
    assert((normalize and imageFeatures) or (not normalize))

    local Tensor = torch.Tensor
    dataset.images = Tensor(dataset.images)
    for i, q in ipairs(dataset.questions) do
        dataset.questions[i] = Tensor(q)
    end
    dataset.answers = Tensor(dataset.answers)
    if tfidf then
        for i, t in ipairs(dataset.tfidfs) do
            dataset.tfidfs[i] = Tensor(t)
        end
    end
    if normalize then
        --[[
        local mean = imageFeatures[1]:clone()
        for i=2,imageFeatures:size(1) do
            mean:add(imageFeatures[i])
        end
        mean:div(imageFeatures:size(1))
        std = (imageFeatures[1]-mean):pow(2)
        for i=2,imageFeatures:size(1) do
            std:add((imageFeatures[i]-mean):pow(2))
        end
        std:div(imageFeatures:size(1)-1)
        std:sqrt()
        ]]

        local images = dataset.images
        local mean = imageFeatures[images[1]]:clone()
        for i=2,images:size(1) do
            mean:add(imageFeatures[images[i]])
        end
        mean:div(images:size(1))

        local std = (imageFeatures[images[1]]-mean):pow(2)
        for i=2,images:size(1) do
            std:add((imageFeatures[images[i]]-mean):pow(2))
        end
        std:div(images:size(1)-1)
        std:sqrt()
        
        for i=1,imageFeatures:size(1) do
            imageFeatures[i]:csub(mean):cdiv(std)
        end
    end
        
    if cacheFeature then
        dataset.images = util.assemble(dataset.images, imageFeatures)
    end

    function dataset:size()
        return self.nsample
    end

    dataset.current_index = 0

    function dataset:reset()
        self.current_index = 0
    end

    function dataset:_next()
        self.current_index = self.current_index + 1
        local index = self.current_index
        if index > self:size() then
            return nil
        end
        if tfidf then
            return self.images[index], self.questions[index], 
                   self.answers[index], self.tfidfs[index]
        end
        return self.images[index], self.questions[index], self.answers[index]
    end
    if disability == 'blind' then
        function dataset:next()
            local _, Q, A, T = dataset:_next()
            if tfidf then
                return {Q, T}, A
            else
                return Q, A
            end
        end
    elseif cacheFeature then
        if not disability then
            function dataset:next()
                local V, Q, A, T = dataset:_next()
                if tfidf then
                    return {V, Q, T}, A
                else
                    return {V, Q}, A
                end
            end
        elseif disability == 'deaf' then
            function dataset:next()
                local V, _, A, T = dataset:_next()
                if tfidf then
                    return {V, T}, A
                else
                    return V, A
                end
            end
        end
    else
        if not disability then
            function dataset:next()
                local V, Q, A, T = dataset:_next()
                if type(imageFeatures) == 'table' then
                    local hV = imageFeatures[1][V]
                    local lV = imageFeatures[2][V]
                    if self.cuda then
                        hV = hV:cuda()
                        lV = lV:cuda()
                    end
                    if tfidf then
                        return {hV, lV, Q, T}, A
                    else
                        return {hV, lV, Q}, A
                    end
                else
                    V = imageFeatures[V]
                    if self.cuda then
                        V = V:cuda()
                    end
                    if tfidf then
                        return {V, Q, T}, A
                    else
                        return {V, Q}, A
                    end
                end
            end
        elseif disability == 'deaf' then
            function dataset:next()
                local V, Q, A, T = dataset:_next()
                if type(imageFeatures) == 'table' then
                    local hV = imageFeatures[1][V]
                    local lV = imageFeatures[2][V]
                    if self.cuda then
                        hV = hV:cuda()
                        lV = lV:cuda()
                    end
                    if tfidf then
                        return {hV, lV, T}, A
                    else
                        return {hV, lV}, A
                    end
                else
                    V = imageFeatures[V]
                    if self.cuda then
                        V = V:cuda()
                    end
                    if tfidf then
                        return {V, T}, A
                    else
                        return V, A
                    end
                end
            end
        end
    end

    function dataset:cuda()
        self.images = self.images:cuda()
        for i, q in ipairs(self.questions) do
            self.questions[i] = q:cuda()
        end
        self.answers = self.answers:cuda()
        if self.tfidfs then
            for i, t in ipairs(self.tfidfs) do
                self.tfidfs[i] = t:cuda()
            end
        end
        self.cuda = true
    end
end

return COCODatasetWrapper
