require 'nn'
require 'torch'
require 'optim'
require 'image'
require 'misc.DataLoader'
require 'misc.word_level'
require 'misc.phrase_level'
require 'misc.ques_level'
require 'misc.recursive_atten'
require 'misc.cnnModel'
require 'misc.optim_updates'
utils = require 'misc.utils'
require 'xlua'

if model_type == nil then
	model_type = 'VGG'
end

function load_vgg()
	opt = {}

	opt.vqa_model = 'model/vqa_model/model_alternating_train-val_vgg.t7'
	opt.cnn_proto = 'image_model/VGG_ILSVRC_19_layers_deploy.prototxt'
	opt.cnn_model = 'image_model/VGG_ILSVRC_19_layers.caffemodel'
	opt.json_file = 'data/vqa_data_prepro_all.json'
	opt.backend = 'cudnn'
	opt.gpuid = 1
	if opt.gpuid >= 0 then
		require 'cutorch'
		require 'cunn'
		if opt.backend == 'cudnn' then 
		require 'cudnn' 
		end
		--cutorch.setDevice(opt.gpuid+1) -- note +1 because lua is 1-indexed
	end

	local loaded_checkpoint = torch.load(opt.vqa_model)
	local lmOpt = loaded_checkpoint.lmOpt

	lmOpt.hidden_size = 512
	lmOpt.feature_type = 'VGG'
	lmOpt.atten_type = 'Alternating'
	cnnOpt = {}
	cnnOpt.cnn_proto = opt.cnn_proto
	cnnOpt.cnn_model = opt.cnn_model
	cnnOpt.backend = opt.backend
	cnnOpt.input_size_image = 512
	cnnOpt.output_size = 512
	cnnOpt.h = 14
	cnnOpt.w = 14
	cnnOpt.layer_num = 37

	-- load the vocabulary and answers.

	local json_file = utils.read_json(opt.json_file)
	ix_to_word = json_file.ix_to_word
	ix_to_ans = json_file.ix_to_ans

	word_to_ix = {}
	for ix, word in pairs(ix_to_word) do
		word_to_ix[word]=ix
	end

	-- load the model
	protos = {}
	protos.word = nn.word_level(lmOpt)
	protos.phrase = nn.phrase_level(lmOpt)
	protos.ques = nn.ques_level(lmOpt)

	protos.atten = nn.recursive_atten()
	protos.crit = nn.CrossEntropyCriterion()
	protos.cnn = nn.cnnModel(cnnOpt)

	if opt.gpuid >= 0 then
		for k,v in pairs(protos) do v:cuda() end
	end

	cparams, grad_cparams = protos.cnn:getParameters()
	wparams, grad_wparams = protos.word:getParameters()
	pparams, grad_pparams = protos.phrase:getParameters()
	qparams, grad_qparams = protos.ques:getParameters()
	aparams, grad_aparams = protos.atten:getParameters()

	print('Load the weight...')
	wparams:copy(loaded_checkpoint.wparams)
	pparams:copy(loaded_checkpoint.pparams)
	qparams:copy(loaded_checkpoint.qparams)
	aparams:copy(loaded_checkpoint.aparams)

	print('total number of parameters in cnn_model: ', cparams:nElement())
	assert(cparams:nElement() == grad_cparams:nElement())

	print('total number of parameters in word_level: ', wparams:nElement())
	assert(wparams:nElement() == grad_wparams:nElement())

	print('total number of parameters in phrase_level: ', pparams:nElement())
	assert(pparams:nElement() == grad_pparams:nElement())

	print('total number of parameters in ques_level: ', qparams:nElement())
	assert(qparams:nElement() == grad_qparams:nElement())
	protos.ques:shareClones()

	print('total number of parameters in recursive_attention: ', aparams:nElement())
	assert(aparams:nElement() == grad_aparams:nElement())

	protos.word:evaluate()
	protos.phrase:evaluate()
	protos.ques:evaluate()
	protos.atten:evaluate()
	protos.cnn:evaluate()
end

function load_res()
	opt = {}

	opt.vqa_model = 'model/vqa_model/model_alternating_train-val_residual.t7'
	opt.cnn_model = 'image_model/resnet-200.t7'
	opt.json_file = 'data/vqa_data_prepro_all.json'
	opt.backend = 'cudnn'
	opt.gpuid = 1
	if opt.gpuid >= 0 then
		require 'cutorch'
		require 'cunn'
		if opt.backend == 'cudnn' then 
		require 'cudnn' 
		end
		--cutorch.setDevice(opt.gpuid+1) -- note +1 because lua is 1-indexed
	end

	local loaded_checkpoint = torch.load(opt.vqa_model)
	local lmOpt = loaded_checkpoint.lmOpt

	lmOpt.hidden_size = 512
	lmOpt.feature_type = 'Residual'
	lmOpt.atten_type = 'Alternating'

	-- load the vocabulary and answers.

	local json_file = utils.read_json(opt.json_file)
	ix_to_word = json_file.ix_to_word
	ix_to_ans = json_file.ix_to_ans

	word_to_ix = {}
	for ix, word in pairs(ix_to_word) do
		word_to_ix[word]=ix
	end

	-- load the model
	protos = {}
	protos.word = nn.word_level(lmOpt)
	protos.phrase = nn.phrase_level(lmOpt)
	protos.ques = nn.ques_level(lmOpt)

	protos.atten = nn.recursive_atten()
	protos.crit = nn.CrossEntropyCriterion()
	--------------------------------------------
	print('loading Residual model...')
	local model = torch.load(opt.cnn_model)
	for i = 14,12,-1 do
		model:remove(i)
	end
	--print(model)
	model:add(nn.View(-1, 2048, 196))
	model:add(nn.Transpose({2,3}))
	protos.cnn=model:cuda()
	model = nil
	--------------------------------------------

	if opt.gpuid >= 0 then
		for k,v in pairs(protos) do v:cuda() end
	end

	cparams, grad_cparams = protos.cnn:getParameters()
	wparams, grad_wparams = protos.word:getParameters()
	pparams, grad_pparams = protos.phrase:getParameters()
	qparams, grad_qparams = protos.ques:getParameters()
	aparams, grad_aparams = protos.atten:getParameters()

	print('Load the weight...')
	wparams:copy(loaded_checkpoint.wparams)
	pparams:copy(loaded_checkpoint.pparams)
	qparams:copy(loaded_checkpoint.qparams)
	aparams:copy(loaded_checkpoint.aparams)

	print('total number of parameters in cnn_model: ', cparams:nElement())
	assert(cparams:nElement() == grad_cparams:nElement())

	print('total number of parameters in word_level: ', wparams:nElement())
	assert(wparams:nElement() == grad_wparams:nElement())

	print('total number of parameters in phrase_level: ', pparams:nElement())
	assert(pparams:nElement() == grad_pparams:nElement())

	print('total number of parameters in ques_level: ', qparams:nElement())
	assert(qparams:nElement() == grad_qparams:nElement())
	protos.ques:shareClones()

	print('total number of parameters in recursive_attention: ', aparams:nElement())
	assert(aparams:nElement() == grad_aparams:nElement())
end

if model_type == 'VGG' then
	load_vgg()
end
if model_type == 'Residual' then
	load_res()
end

function compute_image_features(img_path)
	local img = image.load(img_path)
	img = image.scale(img,448,448)
	--itorch.image(img) --show the image in iTorch
	img = img:view(1,img:size(1),img:size(2),img:size(3))
	local image_raw = utils.prepro(img, false)
	image_raw = image_raw:cuda()
	image_feat = protos.cnn:forward(image_raw)
end

function get_coattention_features(question)
	local ques_encode = torch.IntTensor(26):zero()
	local count = 1
	for word in string.gmatch(question, "%S+") do
		ques_encode[count] = word_to_ix[word] or word_to_ix['UNK']
		count = count + 1
	end
	ques_encode = ques_encode:view(1,ques_encode:size(1))
	ques_encode = ques_encode:cuda()

	local ques_len = torch.Tensor(1,1):cuda()
	ques_len[1] = count-1

	local word_feat, img_feat, w_ques, w_img, mask = unpack(protos.word:forward({ques_encode, image_feat}))
	local conv_feat, p_ques, p_img = unpack(protos.phrase:forward({word_feat, ques_len, img_feat, mask}))
	local q_ques, q_img = unpack(protos.ques:forward({conv_feat, ques_len, img_feat, mask}))

	local feature_ensemble = {w_ques:clone(), w_img:clone(), p_ques:clone(), p_img:clone(), q_ques:clone(), q_img:clone()}
	return feature_ensemble
end

function combine1(questions)
	local nQ = table.getn(questions)
	local nW = table.getn(w)
	local n = math.min(nQ, nW)

	local coatt = {}
	for i = 1, n do
		coatt[i] = get_coattention_features(questions[i])
	end

	if nQ < nW then
		local s = 0
		for i = nQ+1, nW do
			s = s+w[i]
		end
		s = s/nQ
		for i = 1, nQ do
			w[i] = w[i]+s
		end
	end

	for j = 1, table.getn(coatt[1]) do
		coatt[1][j] = w[1]*coatt[1][j]
	end
	for i = 2, n do
		for j = 1, table.getn(coatt[i]) do
			coatt[1][j] = coatt[1][j]+w[i]*coatt[i][j]
		end
	end

	return coatt[1]
end

combine = {combine1}

--call_counter = 1
function get_answer(img_path, questions, expr)
	-- the weights should be non-negative and sum up to 1
	local c = 0
	if expr>=1 and expr<=3 then
		c = 1
		w = {0.6, 0.3, 0.1, 0.1}
	elseif expr>=4 and expr<=6 then
		c = 1
		w = {0.5, 0.4, 0.1, 0.1}
	elseif expr>=7 and expr<=9 then
		c = 1
		w = {0.5, 0.2, 0.2, 0.1}
	elseif expr>=10 and expr<=12 then
		c = 1
		w = {0.4, 0.2, 0.2, 0.2}
	elseif expr>=13 and expr<=15 then
		c = 1
		w = {0.7, 0.1, 0.1, 0.1}
	end
	--if call_counter%1000==0 then
	--	collectgarbage()
	--end
	compute_image_features(img_path)
	local feature_ensemble = combine[c](questions)
	local out_feat = protos.atten:forward(feature_ensemble)
	local tmp,pred=torch.max(out_feat,2)
	local ans = ix_to_ans[tostring(pred[1][1])]
	return ans
end

function demo()
	local img_path = 'vis/demo_img1.jpg'

	local questions = {}
	questions[1] = 'what is the color of the hat ?' 
	questions[2] = 'what is the name of the socks ?' 
	questions[3] = 'is the man wearing socks ?'

	local ans = get_answer(img_path, questions, combine1)
	print(ans)
end