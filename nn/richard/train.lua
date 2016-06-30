-- training script
-- https://github.com/htwaijry/npy4th
c = require 'trepl.colorize'
npy4th = require 'npy4th'
lapp = require 'pl.lapp'
require 'math'
require 'xlua'
require 'optim'
print(c.yellow 'starting...')
local args = lapp [[
    --save               (default "model_default.net"            save model name)
    --output_dir         (default "output/")                     directory to save the model output
    --model              (default "models/model_baseline.lua")   location of saving the model, full lua filename
    --batch_size         (default 2)                             minibatch size
    --dropout            (default 0.0) 
    --init_weight        (default 0.1)                           random weight initialization limits
    --lr                 (default .001)                          learning rate
    --epochs             (default 4)                             when to start decaying learning rate
    --gpu                                                        train the gru network
    --weigtDecay         (default 0)                             SGD only
    --momentum           (default 0)                             SGD only
    --train_images       (default '/home/rnam/Documents/ped/data/20160626_snapshot/tensors/X_dev.npy') training images
    --train_labels       (default '/home/rnam/Documents/ped/data/20160626_snapshot/tensors/y_dev.npy') training labels
    --test_images        (default '/home/rnam/Documents/ped/data/20160626_snapshot/tensors/X_val.npy') test images
    --test_labels        (default '/home/rnam/Documents/ped/data/20160626_snapshot/tensors/y_val.npy') test labels
    ]]

print(args)
if args.gpu then
    print(c.red 'training on the gpu')
    require 'cunn'
else
    print(c.red 'not training on the gpu')
    require 'nn'
end
-- define optimzation criterion
optimState = {
    learningRate = args.lr,
    weightDecay = args.weightDecay,
    momentum = args.momentum,
    learningRateDecay = 1e-7}
optimMethod = optim.asgd
-- import model
print(c.blue '===>'..' configuring model')
if args.gpu then
    local model = nn.Sequential()
    model:add(dofile(args.model))
    model = model:cuda()
    criterion = nn.ClassNLLCriterion():cuda()
    print(model)
else
    local model = nn.Sequential()
    model:add(dofile(args.model))
    criterion = nn.ClassNLLCriterion()
    print(model)
end
if model then
   parameters,gradParameters = model:getParameters()
end
-- load data
print(c.blue '===>'..' loading data')
dimage = npy4th.loadnpy(args.train_images):double()
dlabel = npy4th.loadnpy(args.train_labels):double() + 1
test_image = npy4th.loadnpy(args.test_images):double()
test_label = npy4th.loadnpy(args.test_labels):double() + 1
if args.gpu then dimage = dimage:cuda() end
if args.gpu then test_image = test_image:cuda() end
trainset = {}
function trainset:size() return dimage:size()[1] end
-- new training methods
print(c.blue '===>'..' training')
for e=1, args.epochs do
    -- confusion matrix for training
    classes = {'1','2'}
    confusion = optim.ConfusionMatrix(classes)
    rand = torch.randperm(trainset:size()) -- randomize indexes
    for step=1, trainset:size(), args.batch_size do
        -- disp progress
        xlua.progress(step, trainset:size())
        local labels = {}
        local images = {}
        for i=step, math.min(step+args.batch_size, trainset:size()) do
            label = dlabel[rand[i]]
            image = dimage[rand[i]]
            table.insert(labels, label)
            table.insert(images, image)
        end
        -- mini-batch evaluation
        local feval = function(x)
            -- new parameters
            if x ~= parameters then
                parameters:copy(x)
            end
            -- reset gradients
            gradParameters:zero()
            -- mean of all the criterions
            f = 0
            -- evalute for the entire mini-batch
            for j=1, #images do
                D = images[j]
                glabel = labels[j]
                -- estimate f (for the entire mini-batch)
                local output = model:forward(D)
                local err = criterion:forward(output, glabel)
                f = f + err
                -- compute the derivative and update the model
                local df = criterion:backward(output, glabel)
                model:backward(D, df)
                -- update confusion
                confusion:add(output, glabel)

            end
            -- normalize the gradients
            gradParameters:div(#images)
            f = f/#images
            return f, gradParameters
        end
        _new_x, _fx , _average = optimMethod(feval, parameters, optimState)     

    end
    print(c.yellow 'Completed epoch: '..e)
    print(confusion)
    -- evaluate the model after N number of epochs
    if e % 5 == 0 then
        print(c.red '===>'..' Evaluate at epoch: '..e)
        _confusion = optim.ConfusionMatrix(classes)
        model:evaluate()
        for _t = 1, test_image:size()[1] do
            xlua.progress(_t, test_image:size()[1])
            _input = test_image[_t]
            _target = test_label[_t]
            local _pred = model:forward(_input)
            _confusion:add(_pred, _target)
        end
        print(_confusion)
        print('==> Saving model to '..args.output_dir..args.save)
        torch.save(args.output_dir..args.save, model)
    end
end

timer = torch.Timer()
print('Time elapsed for '..args.epochs..' epochs ' .. timer:time().real/60 .. ' minutes')
print(c.yellow 'made it to the end')






